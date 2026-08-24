locals {
  common_tags = {
    Project     = "Mission-AWS"
    Environment = "Dev"
    Owner       = "Aviv"
  }
}
locals {
  # יצירת מילון של סוגי שרתים לפי סביבה
  instance_sizes = {
    default = "t3.micro"
    dev     = "t3.micro"
    prod    = "t3.large"
  }

  # שליפת הגודל המתאים לפי הסביבה הנוכחית
  env_instance_type = local.instance_sizes[terraform.workspace]
}