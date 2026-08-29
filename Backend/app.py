import os
import json
import psycopg2
from psycopg2.extras import RealDictCursor
import boto3
from flask import Flask, render_template_string, request, redirect, url_for, flash, Response, jsonify
from flask_cors import CORS
from datetime import datetime
from prometheus_flask_exporter import PrometheusMetrics
from prometheus_client import Counter # <-- תוספת המדדים העסקיים

app = Flask(__name__)

# פקודה זו עוטפת את האפליקציה ומייצרת אוטומטית את נתיב ה-/metrics
metrics = PrometheusMetrics(app)

# --- Custom Business Metrics (Page 3 Requirement) ---
INFRA_CREATED_METRIC = Counter('business_infra_created_total', 'Total number of infrastructure configurations successfully created')
INFRA_DELETED_METRIC = Counter('business_infra_deleted_total', 'Total number of infrastructure configurations deleted', ['deletion_type'])

# סגירת פרצת ה-CORS: מאפשרים גישה רק למה שמגיע מה-Frontend שלנו
FRONTEND_URL = os.getenv("FRONTEND_URL", "*")
CORS(app, resources={r"/*": {"origins": FRONTEND_URL}})

app.secret_key = os.getenv("SECRET_KEY", "default-dev-key")

# --- AWS Configuration ---
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL")
S3_BUCKET_NAME = os.getenv("S3_BUCKET")
SNS_TOPIC_ARN = os.getenv("SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:544471418394:aviv-project-alerts-v2").strip()
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

s3_client = boto3.client('s3', region_name=AWS_REGION)
sns_client = boto3.client('sns', region_name=AWS_REGION)
sqs_client = boto3.client('sqs', region_name=AWS_REGION)

# --- Database Configuration ---
DB_CONFIG = {
    "host": os.getenv("DB_HOST"),
    "database": os.getenv("DB_NAME", "postgres"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD"),
    "sslmode": "require"
}

# --- HTML Template ---
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Infrastructure Setup</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        .bg-brand { background-color: #635BFF; }
        .hover-bg-brand:hover { background-color: #5048E5; }
        body { background-color: #F8F9FC; }
        .modal { transition: opacity 0.25s ease; }
        body.modal-active { overflow: hidden; }
        .checkbox-custom { width: 1.2rem; height: 1.2rem; cursor: pointer; accent-color: #635BFF; }
    </style>
</head>
<body class="min-h-screen text-slate-800 font-sans">

    <div class="p-6 flex justify-between items-start">
        <div class="flex flex-col gap-2 text-sm font-medium text-gray-600">
            <div class="bg-white px-4 py-2 rounded-lg shadow-sm border border-gray-100 flex items-center gap-2">
                <span class="w-2.5 h-2.5 bg-green-500 rounded-full animate-pulse"></span>
                Backend <span class="text-green-500 ml-1">Online</span>
            </div>
            <div class="bg-white px-4 py-2 rounded-lg shadow-sm border border-gray-100 flex items-center gap-2">
                <span class="w-2.5 h-2.5 bg-green-500 rounded-full animate-pulse"></span>
                Auth <span class="text-green-500 ml-1">Online</span>
            </div>
        </div>
        <div class="flex items-center gap-4 bg-white px-6 py-3 rounded-full shadow-sm border border-gray-100">
            <span class="text-gray-700 font-medium">Welcome, Aviv Negbi 👋</span>
            <div class="h-6 w-px bg-gray-200 mx-2"></div>
            <button class="text-gray-600 hover:text-brand flex items-center gap-2 text-sm font-semibold">
                <i class="fa-solid fa-user"></i> My Profile
            </button>
        </div>
    </div>

    <div class="max-w-5xl mx-auto px-4 pb-20">

        {% with messages = get_flashed_messages(with_categories=true) %}
            {% if messages %}
                {% for category, message in messages %}
                    <div class="mb-6 p-6 rounded-2xl shadow-lg border-l-8 flex justify-between items-center {% if category == 'success' %} bg-green-50 border-green-500 text-green-800 {% else %} bg-red-50 border-red-500 text-red-800 {% endif %}">
                        <div>
                            <i class="fa-solid {% if category == 'success' %}fa-circle-check text-green-500{% else %}fa-circle-exclamation text-red-500{% endif %} text-xl mr-3"></i>
                            <span class="font-bold text-lg">{{ message }}</span>
                        </div>
                        {% if category == 'success' and last_id %}
                        <button onclick="fetchPreview({{ last_id }})" class="bg-brand hover-bg-brand text-white px-6 py-2 rounded-xl font-bold transition-all shadow-md flex items-center gap-2">
                            <i class="fa-solid fa-eye"></i> Preview Configuration
                        </button>
                        {% endif %}
                    </div>
                {% endfor %}
            {% endif %}
        {% endwith %}

        <div class="bg-white rounded-[2rem] shadow-xl shadow-indigo-100/50 border border-gray-100 p-12 mb-12">
            <h1 class="text-3xl font-bold text-center mb-10 text-gray-900 tracking-tight">Infrastructure Setup</h1>
            <form action="/add" method="POST" class="grid grid-cols-1 md:grid-cols-2 gap-x-10 gap-y-8">
                <div>
                    <label class="block text-sm font-semibold text-gray-700 mb-2 text-center">Number of Instances</label>
                    <input type="number" name="instances" value="2" min="1" max="10" class="w-full bg-gray-50 border border-gray-200 rounded-xl p-3.5 text-center outline-none focus:ring-2 focus:ring-brand">
                </div>
                <div>
                    <label class="block text-sm font-semibold text-gray-700 mb-2 text-center">Base Machine Name</label>
                    <input type="text" name="name" placeholder="PROJECT-X" required class="w-full bg-gray-50 border border-gray-200 rounded-xl p-3.5 text-center outline-none focus:ring-2 focus:ring-brand">
                </div>
                <div>
                    <label class="block text-sm font-semibold text-gray-700 mb-2 text-center">Operating System</label>
                    <select name="os" class="w-full bg-gray-50 border border-gray-200 rounded-xl p-3.5 text-center outline-none bg-white">
                        <option>Ubuntu 22.04 LTS</option>
                        <option>Amazon Linux 2023</option>
                    </select>
                </div>
                <div>
                    <label class="block text-sm font-semibold text-gray-700 mb-2 text-center">Instance Type</label>
                    <select name="instance_type" class="w-full bg-gray-50 border border-gray-200 rounded-xl p-3.5 text-center outline-none bg-white">
                        <option value="t2.nano">t2.nano (1 vCPU, 0.5GB RAM)</option>
                        <option value="t2.micro">t2.micro (1 vCPU, 1GB RAM)</option>
                    </select>
                </div>
                <div>
                    <label class="block text-sm font-semibold text-gray-700 mb-2 text-center">Post-Launch Script</label>
                    <select name="script" class="w-full bg-gray-50 border border-gray-200 rounded-xl p-3.5 text-center outline-none bg-white">
                        <option>Install & Configure Nginx</option>
                        <option>Docker Setup</option>
                        <option>None</option>
                    </select>
                </div>
                <div>
                    <label class="block text-sm font-semibold text-gray-700 mb-2 text-center">Output Type</label>
                    <select name="output_type" class="w-full bg-gray-50 border border-blue-400 ring-2 ring-blue-50 rounded-xl p-3.5 text-center outline-none bg-white font-bold text-blue-600">
                        <option>JSON Configuration</option>
                        <option>Terraform (.tf) File</option>
                    </select>
                </div>
                <div class="md:col-span-2 mt-4">
                    <button type="submit" class="w-full bg-brand hover-bg-brand text-white font-bold text-lg py-4 rounded-2xl transition-all shadow-lg shadow-indigo-100 flex items-center justify-center gap-2">
                        <i class="fa-solid fa-plus-circle"></i> Create Instances
                    </button>
                </div>
            </form>
        </div>

        <div class="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
            <div class="p-6 border-b border-gray-50 flex justify-between items-center bg-gray-50/50">
                <div class="flex items-center gap-4">
                    <h2 class="text-xl font-bold text-gray-800 tracking-tight">Active Infrastructure</h2>
                    <span class="bg-indigo-100 text-indigo-700 px-3 py-1 rounded-full text-xs font-bold">{{ data_rows|length }} Active</span>
                </div>
                <button id="bulkDeleteBtn" onclick="deleteSelected()" class="hidden bg-red-500 hover:bg-red-600 text-white px-4 py-2 rounded-xl text-sm font-bold transition-all flex items-center gap-2">
                    <i class="fa-solid fa-trash-can"></i> Delete Selected (<span id="selectedCount">0</span>)
                </button>
            </div>
            <table class="w-full text-left">
                <thead class="bg-gray-50 text-gray-400 text-xs uppercase tracking-widest">
                    <tr>
                        <th class="p-5 w-10 text-center">
                            <input type="checkbox" id="selectAll" onclick="toggleAll(this)" class="checkbox-custom rounded">
                        </th>
                        <th class="p-5 font-semibold">ID</th>
                        <th class="p-5 font-semibold">Name</th>
                        <th class="p-5 font-semibold text-center">Instance Type</th>
                        <th class="p-5 font-semibold text-right">Actions</th>
                    </tr>
                </thead>
                <tbody class="divide-y divide-gray-50">
                    {% for row in data_rows %}
                    <tr class="hover:bg-gray-50/50 transition-colors">
                        <td class="p-5 text-center">
                            <input type="checkbox" class="instance-checkbox checkbox-custom rounded" value="{{ row['id'] }}" onclick="updateBulkDeleteVisibility()">
                        </td>
                        <td class="p-5 text-gray-400 font-mono">#{{ row['id'] }}</td>
                        <td class="p-5 font-bold text-gray-700">{{ row['name'] }}</td>
                        <td class="p-5 text-center">
                            <span class="px-3 py-1.5 rounded-lg text-xs font-bold bg-green-100 text-green-700 border border-green-200">
                                {{ row['display_type'] }}
                            </span>
                        </td>
                        <td class="p-5 text-right flex justify-end gap-2">
                            <button onclick="fetchPreview({{ row['id'] }})" class="text-indigo-400 hover:text-indigo-600 p-2"><i class="fa-solid fa-eye text-lg"></i></button>
                            <form action="/delete/{{ row['id'] }}" method="POST" class="inline" onsubmit="return confirm('Delete this instance?');">
                                <button class="text-red-300 hover:text-red-500 p-2"><i class="fa-solid fa-trash-can text-lg"></i></button>
                            </form>
                        </td>
                    </tr>
                    {% endfor %}
                </tbody>
            </table>
        </div>
    </div>

    <div id="modal" class="modal opacity-0 pointer-events-none fixed w-full h-full top-0 left-0 flex items-center justify-center z-50">
        <div class="modal-overlay absolute w-full h-full bg-gray-900 opacity-60"></div>
        <div class="modal-container bg-white w-11/12 md:max-w-2xl mx-auto rounded-[2rem] shadow-2xl z-50 overflow-hidden">
            <div class="modal-content py-8 px-10 text-left">
                <div class="flex justify-between items-center pb-5 border-b border-gray-100 mb-6">
                    <p class="text-xl font-bold text-gray-800" id="modalFileName">infra_config.json</p>
                    <div class="cursor-pointer text-gray-400 hover:text-gray-600" onclick="closeModal()">
                        <i class="fa-solid fa-xmark text-2xl"></i>
                    </div>
                </div>
                <div class="bg-slate-900 rounded-2xl p-6">
                    <pre class="text-blue-300 font-mono text-sm leading-relaxed overflow-x-auto" id="jsonPreview">Loading...</pre>
                </div>
                <div class="flex justify-end pt-8 gap-4">
                    <button onclick="closeModal()" class="px-6 py-2 bg-gray-100 text-gray-500 font-bold rounded-xl hover:bg-gray-200 transition-all">Close</button>
                    <a id="downloadBtn" href="#" class="px-8 py-2 bg-brand text-white font-bold rounded-xl hover-bg-brand shadow-lg shadow-indigo-100 transition-all flex items-center gap-2">
                        <i class="fa-solid fa-download"></i> Download Full JSON
                    </a>
                </div>
            </div>
        </div>
    </div>

    <script>
        function toggleAll(source) {
            const checkboxes = document.querySelectorAll('.instance-checkbox');
            checkboxes.forEach(cb => cb.checked = source.checked);
            updateBulkDeleteVisibility();
        }

        function updateBulkDeleteVisibility() {
            const checkboxes = document.querySelectorAll('.instance-checkbox:checked');
            const bulkBtn = document.getElementById('bulkDeleteBtn');
            const countSpan = document.getElementById('selectedCount');
            countSpan.innerText = checkboxes.length;
            if (checkboxes.length > 0) { bulkBtn.classList.remove('hidden'); }
            else {
                bulkBtn.classList.add('hidden');
                document.getElementById('selectAll').checked = false;
            }
        }

        function deleteSelected() {
            const checkboxes = document.querySelectorAll('.instance-checkbox:checked');
            const ids = Array.from(checkboxes).map(cb => cb.value);
            if (confirm(`Are you sure you want to delete ${ids.length} instances?`)) {
                fetch('/delete_multiple', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ ids: ids })
                })
                .then(res => res.json())
                .then(data => {
                    if (data.status === 'success') { window.location.reload(); }
                    else { alert("Error during bulk delete"); }
                });
            }
        }

        function fetchPreview(id) {
            fetch(`/api/preview/${id}`)
                .then(res => res.json())
                .then(data => {
                    document.getElementById('jsonPreview').innerText = JSON.stringify(data, null, 4);
                    document.getElementById('modalFileName').innerText = "config_" + data.Base_Machine_Name + ".json";
                    document.getElementById('downloadBtn').href = "/download/" + id;
                    const modal = document.getElementById('modal');
                    modal.classList.remove('opacity-0', 'pointer-events-none');
                    document.body.classList.add('modal-active');
                });
        }

        function closeModal() {
            const modal = document.getElementById('modal');
            modal.classList.add('opacity-0', 'pointer-events-none');
            document.body.classList.remove('modal-active');
        }
    </script>
</body>
</html>
"""

def get_db_connection():
    DB_CONFIG['sslmode'] = 'require'
    return psycopg2.connect(**DB_CONFIG)

# --- הוספת נתיב Healthcheck חכם ---
@app.route('/health')
def health_check():
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
        return jsonify({"status": "healthy", "db": "connected"}), 200
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 503

@app.route('/error-drill')
def error_drill():
    return jsonify({"status": "error", "message": "Simulating high error rate!"}), 500

@app.route('/')
def index():
    rows = []
    last_id = request.args.get('last_id')
    try:
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # התיקון כאן: הוסר ה- WHERE id > 4
                cur.execute("SELECT id, name, status FROM mission_data ORDER BY id DESC;")
                db_rows = cur.fetchall()
                for r in db_rows:
                    try:
                        data = json.loads(r['status'])
                        r['display_type'] = data.get('Instance_Type', 'Unknown')
                    except:
                        r['display_type'] = r['status']
                    rows.append(r)
    except Exception as e:
        flash(f"DB Error: {e}", "error")
    return render_template_string(HTML_TEMPLATE, data_rows=rows, last_id=last_id)

@app.route('/add', methods=['POST'])
def add_entry():
    name = request.form.get('name')
    instances = request.form.get('instances')
    os_type = request.form.get('os')
    instance_type = request.form.get('instance_type')
    script = request.form.get('script')
    output_type = request.form.get('output_type')

    if name and instance_type:
        try:
            # התיקון שלנו: חותמת זמן דינמית ואמיתית!
            current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

            full_payload = {
                "Base_Machine_Name": name,
                "Number_of_Instances": instances,
                "Operating_System": os_type,
                "Instance_Type": instance_type,
                "Post_Launch_Script": script,
                "Infrastructure_Output_Type": output_type,
                "Created_At": current_time
            }
            with get_db_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("INSERT INTO mission_data (name, status) VALUES (%s, %s) RETURNING id;", (name, json.dumps(full_payload)))
                    new_id = cur.fetchone()[0]

            s3_key = f"logs/config_{name}.json"
            s3_client.put_object(Bucket=S3_BUCKET_NAME, Key=s3_key, Body=json.dumps(full_payload, indent=4))

            sqs_message = {
                "s3_bucket": S3_BUCKET_NAME,
                "s3_key": s3_key,
                "action": "process_infra"
            }
            sqs_client.send_message(QueueUrl=SQS_QUEUE_URL, MessageBody=json.dumps(sqs_message))

            sns_message = f"""
======= 🚀 CLOUD DEPLOYMENT ALERT =======
📌 Project: {name}
-------------------------------------------
🖥️  Type:      {instance_type}
🔢  Quantity:  {instances}
💿  OS:        {os_type}
📜  Script:    {script}
📦  Output:    {output_type}
🕒  Created:   {current_time}
-------------------------------------------
✅ Status: All details saved to RDS & S3
🛠️  Managed by: Aviv's Cloud Infrastructure
===========================================
"""
            sns_client.publish(TopicArn="arn:aws:sns:us-east-1:544471418394:aviv-project-alerts-v2", Message=sns_message, Subject=f"Full Config Created: {name}")

            # --- עדכון המדד העסקי של פרומתיאוס (הקפצת יצירה) ---
            INFRA_CREATED_METRIC.inc()

            flash(f"Successfully created '{name}'!", "success")
            return redirect(url_for('index', last_id=new_id))
        except Exception as e:
            flash(f"System Error: {str(e)}", "error")
    return redirect(url_for('index'))

@app.route('/api/preview/<int:entry_id>')
def api_preview(entry_id):
    try:
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT status FROM mission_data WHERE id = %s;", (entry_id,))
                row = cur.fetchone()
                return jsonify(json.loads(row['status']))
    except:
        return jsonify({"error": "Not found"}), 404

@app.route('/download/<int:entry_id>')
def download_config(entry_id):
    try:
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT name, status FROM mission_data WHERE id = %s;", (entry_id,))
                row = cur.fetchone()
                full_json = json.loads(row['status'])
                return Response(
                    json.dumps(full_json, indent=4),
                    mimetype="application/json",
                    headers={"Content-disposition": f"attachment; filename=config_{row['name']}.json"}
                )
    except:
        return "Error", 500

@app.route('/delete/<int:entry_id>', methods=['POST'])
def delete_entry(entry_id):
    try:
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT name, status FROM mission_data WHERE id = %s;", (entry_id,))
                row = cur.fetchone()
                if row:
                    name = row['name']
                    details = json.loads(row['status'])

                    del_message = f"""
🗑️ INFRASTRUCTURE REMOVED
------------------------------------------
Asset Name: {name}
Database ID: #{entry_id}

📜 DELETED CONFIG DETAILS:
- Scale:    {details.get('Number_of_Instances', 'N/A')} Nodes
- Machine:  {details.get('Instance_Type', 'N/A')}
- OS:       {details.get('Operating_System', 'N/A')}
- Script:   {details.get('Post_Launch_Script', 'N/A')}
- Output:   {details.get('Infrastructure_Output_Type', 'N/A')}
------------------------------------------
Action: Permanent Deletion Completed.
"""
                    sns_client.publish(TopicArn=SNS_TOPIC_ARN, Message=del_message, Subject=f"Infrastructure Deleted: {name}")
                    cur.execute("DELETE FROM mission_data WHERE id = %s;", (entry_id,))

                    # --- עדכון המדד העסקי של פרומתיאוס (מחיקה בודדת) ---
                    INFRA_DELETED_METRIC.labels(deletion_type='single').inc()

        flash(f"Record '{name}' deleted.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for('index'))

@app.route('/delete_multiple', methods=['POST'])
def delete_multiple():
    data = request.get_json()
    ids = data.get('ids', [])
    if not ids:
        return jsonify({"status": "error"}), 400
    try:
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                id_tuple = tuple(int(i) for i in ids)
                cur.execute("SELECT id, name, status FROM mission_data WHERE id IN %s;", (id_tuple,))
                deleted_rows = cur.fetchall()

                report_items = []
                for r in deleted_rows:
                    det = json.loads(r['status'])
                    report_items.append(f"• {r['name']} (#{r['id']}): {det.get('Number_of_Instances')}x {det.get('Instance_Type')}")

                bulk_message = f"""
🚨 BULK TERMINATION EVENT
------------------------------------------
Total Nodes Purged: {len(ids)}

DETAILED LIST:
{chr(10).join(report_items)}

------------------------------------------
Priority: High - Cleanup successful.
"""
                sns_client.publish(TopicArn=SNS_TOPIC_ARN, Message=bulk_message, Subject="Infrastructure Alert: Bulk Action")
                cur.execute("DELETE FROM mission_data WHERE id IN %s;", (id_tuple,))

                # --- עדכון המדד העסקי של פרומתיאוס (מחיקה מרובה) ---
                INFRA_DELETED_METRIC.labels(deletion_type='bulk').inc(len(ids))

        flash(f"Deleted {len(ids)} instances.", "success")
        return jsonify({"status": "success"})

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)