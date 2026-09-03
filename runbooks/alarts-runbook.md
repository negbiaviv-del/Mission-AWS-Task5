# DevOps Project - Alerts Runbook

This runbook provides troubleshooting steps for the alerts defined in the `devops-app-alerts` PrometheusRule.

---

## 1. HighErrorRate (Application)
**Description:** The application is returning 5xx errors for more than 10% of requests over the last 5 minutes.
**Severity:** Critical
**Troubleshooting Steps:**
1. Check application logs for exceptions: `kubectl logs -l app=backend -n devops-app`
2. Verify database connectivity and check if the database pod is running.
3. Check if a recent deployment introduced breaking changes. If so, initiate a rollback.

## 2. HighLatencyP95 (Application)
**Description:** The 95th percentile latency of HTTP requests is above 2 seconds.
**Severity:** Warning
**Troubleshooting Steps:**
1. Review application logs for slow database queries or external API timeouts.
2. Check pod resource usage (CPU/Memory) using `kubectl top pods -n devops-app`.
3. Consider scaling up the deployment replicas if the load is genuinely high.

## 3. JenkinsQueueStuck (CI/CD)
**Description:** Builds are waiting in the Jenkins queue for more than 1 minute.
**Severity:** Warning
**Troubleshooting Steps:**
1. Log in to the Jenkins UI and navigate to **Manage Jenkins -> Nodes**.
2. Check if the `Built-In Node` or Kubernetes dynamic agents are offline or disconnected.
3. Verify that the Kubernetes cluster has enough resources to spin up new dynamic agent pods.

## 4. ReplicasMismatch (Kubernetes)
**Description:** The number of available replicas is less than the desired replicas for the deployment.
**Severity:** Warning
**Troubleshooting Steps:**
1. List the pods to identify failing ones: `kubectl get pods -n devops-app`
2. Inspect the failing pod's events: `kubectl describe pod <pod-name> -n devops-app`
3. Look for common errors such as `ImagePullBackOff`, `CrashLoopBackOff`, or `OOMKilled`.

## 5. NodeNotReady (Kubernetes)
**Description:** A Kubernetes node has been in a `NotReady` state for more than 2 minutes.
**Severity:** Critical
**Troubleshooting Steps:**
1. Identify the problematic node: `kubectl get nodes`
2. Describe the node to check for resource pressure (Disk/Memory/PID): `kubectl describe node <node-name>`
3. Check the AWS EC2 console to ensure the underlying instance is healthy and running.

## 6. PrometheusTargetDown (Monitoring)
**Description:** A monitoring target (e.g., node-exporter, kube-state-metrics, or the app itself) has disappeared and is unreachable by Prometheus.
**Severity:** Critical
**Troubleshooting Steps:**
1. Open the Prometheus UI and navigate to **Status -> Targets** to identify which specific target is down.
2. Verify that the corresponding Service and Pods for that target are running correctly in Kubernetes.
3. Check if network policies or security groups are blocking Prometheus from scraping the target's `/metrics` endpoint.