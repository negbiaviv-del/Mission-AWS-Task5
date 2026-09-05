# === פתיחת ערוץ תקשורת ישיר (Port Forwarding) לפרומיתיאוס ===
# בודק אם כבר יש חיבור פתוח לפרומיתיאוס על המחשב המקומי (בפורט 9090).
# אם אין, הוא פותח "מנהרה" (Tunnel) ברקע שמעבירה תעבורה מהמחשב שלך ישירות לפוד של פרומיתיאוס בקוברנטיס, כך שתוכל לגשת לממשק שלו דרך הדפדפן שלך בכתובת http://localhost:9090.
if curl -s http://localhost:9090 > /dev/null; then
    echo "✅ Prometheus tunnel is already open!"
else
    echo "⏳ Opening Prometheus tunnel in the background..."
    kubectl port-forward svc/kube-prometheus-stack-prometheus -n observability 9090:9090 > /dev/null 2>&1 &
    sleep 3
    echo "✅ Tunnel is now open at http://localhost:9090"
fi