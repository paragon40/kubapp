source scripts/extra/secret_functions.sh

a=$(mktemp --suffix=.env)
b=$(mktemp --suffix=.env)

cat > "$a" <<'EOF'
master_username=kubapp_admin
master_password=kubapp-password
EOF

cat > "$b" <<'EOF'
master_password="kubapp-password"
master_username="kubapp_admin"
EOF

echo "files_match result:"

if files_match "$a" "$b" dotenv; then
    echo "MATCH"
else
    echo "DIFFER"
fi

rm -f "$a" "$b"
