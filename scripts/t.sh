echo "Checking artifacts"
find . ../artifacts -type d
RE=$?

if [[ "$RE" -eq 0 ]]; then
  echo "Found"
else
  echo "REsult is: $RE"
fi
