#!/bin/bash
set -e

CA_NAME=piron-homelab-ca
DAYS=3650

openssl genrsa -out ${CA_NAME}.key 4096

openssl req -x509 -new -nodes \
  -key ${CA_NAME}.key \
  -sha256 \
  -days ${DAYS} \
  -out ${CA_NAME}.crt \
  -subj "/CN=${CA_NAME}"

echo "CA générée :"
echo " - ${CA_NAME}.crt"
echo " - ${CA_NAME}.key"
