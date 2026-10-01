# ==============================================================================
# 1. יצירת הרשת הווירטואלית המבודדת (VPC)
# ==============================================================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "main-vpc" }
}

# ==============================================================================
# 2. שערי יציאה (Internet Gateway & NAT Gateway)
# ==============================================================================
# Internet Gateway - מאפשר יציאה לאינטרנט עבור הסאבנטים הציבוריים
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "main-igw" }
}

# Elastic IP - כתובת ציבורית קבועה עבור ה-NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "nat-eip" }
}

# NAT Gateway - מאפשר יציאה מאובטחת לאינטרנט עבור הסאבנטים הפרטיים (בהם יושבים שרתי ה-EKS)
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  tags       = { Name = "main-nat-gateway" }
  depends_on = [aws_internet_gateway.gw]
}

# ==============================================================================
# 3. ניתוב תעבורה (Route Tables)
# ==============================================================================
# טבלת ניתוב ציבורית - זורקת תעבורה החוצה לאינטרנט החשוף
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "public-route-table" }
}

# טבלת ניתוב פרטית - זורקת תעבורה החוצה דרך ה-NAT Gateway בלבד
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "private-route-table" }
}

# ==============================================================================
# 4. חלוקה לאזורים (Subnets)
# ==============================================================================
# סאבנטים ציבוריים - כאן AWS יקים את ה-Load Balancers עבור ה-EKS שלנו
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  # תגית קריטית ל-EKS כדי שידע למקם פה את ה-Load Balancer הציבורי
  tags = {
    Name                     = "public-subnet-1"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "public-subnet-2"
    "kubernetes.io/role/elb" = "1"
  }
}

# סאבנטים פרטיים - כאן ירוצו שרתי ה-EKS, הפודים שלנו ומסד הנתונים
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_1_cidr
  availability_zone = "us-east-1a"

  tags = {
    Name                              = "private-subnet-1"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_2_cidr
  availability_zone = "us-east-1b"

  tags = {
    Name                              = "private-subnet-2"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# חיבור הסאבנטים לטבלאות הניתוב שלהם
resource "aws_route_table_association" "pub1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "pub2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "priv1_assoc" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "priv2_assoc" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

# ==============================================================================
# 5. תשתיות מסד נתונים (RDS)
# ==============================================================================
# מאגד את הסאבנטים הפרטיים עבור ה-RDS
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "main-rds-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  tags       = { Name = "Main DB Subnet Group" }
}

# חומת אש (Security Group) פנימית עבור ה-RDS
resource "aws_security_group" "db_sg" {
  name   = "rds-db-sg"
  vpc_id = aws_vpc.main.id

  # מאפשר גישה למסד הנתונים מכל משאב בתוך הרשת הפרטית (כולל שרתי ה-EKS)
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}