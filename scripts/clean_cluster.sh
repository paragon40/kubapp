
# delete argocd applications (if applicationSet is used)
kubectl get applicationsets -n argocd
kubectl delete applicationset kubapp -n argocd 
# or use
kubectl delete -n argocd -f gitops/argocd/appset.yaml


# if not used
kubectl delete applications.argoproj.io ingress admin user -n argocd

#checks
kubectl get applicationsets -n argocd
kubectl get applications -n argocd
kubectl get ingress -A


#check finalizers
kubectl get ingress kubapp-ingress -n ingress -o json | jq '.metadata.finalizers'

# if exist, remove them
kubectl patch ingress kubapp-ingress -n ingress \
-p '{"metadata":{"finalizers":[]}}' --type=merge

# delete namespaces not created by tf
kubectl delete ns ingress admin user argocd
