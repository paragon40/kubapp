
kubectl -n argocd create secret generic repo-kubapp-ssh \
  --from-file=sshPrivateKey=argocd-gitops

argocd repo add git@github.com:paragon40/kubapp.git \
  --ssh-private-key-path argocd-gitops

