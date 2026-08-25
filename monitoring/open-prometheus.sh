if curl -s http://localhost:9090 > /dev/null; then
    echo "✅ Prometheus tunnel is already open!"
else
    echo "⏳ Opening Prometheus tunnel in the background..."
    kubectl port-forward svc/kube-prometheus-stack-prometheus -n observability 9090:9090 > /dev/null 2>&1 &
    sleep 3
    echo "✅ Tunnel is now open at http://localhost:9090"
fi

