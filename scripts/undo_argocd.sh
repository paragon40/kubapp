🛠️ How to fix it (proper order)

Step 1 — Delete ArgoCD properly first
helm uninstall argocd -n argocd

Step 2 — Force delete namespace (if stuck)
kubectl delete namespace argocd --grace-period=0 --force

Step 3 — Remove finalizers (if still stuck)
kubectl get namespace argocd -o json | jq '.spec.finalizers'

Then patch:

kubectl patch namespace argocd \
  -p '{"spec":{"finalizers":[]}}' --type=merge

Step 4 — Delete CRDs manually (important)
kubectl delete crd applications.argoproj.io
kubectl delete crd applicationsets.argoproj.io
kubectl delete crd appprojects.argoproj.io

Step 5 — Retry Terraform destroy
terraform destroy

