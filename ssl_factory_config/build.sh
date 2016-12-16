#!/bin/bash

openssl genpkey -algorithm RSA -out rootkey.pem -pkeyopt rsa_keygen_bits:4096
openssl req -new -key rootkey.pem -days 30 -extensions v3_ca -batch -out root.csr -utf8 -subj '/C=US/O=Orgname Star/OU=SomeInternalName'
# subl openssl.root.cnf
openssl x509 -req -sha256 -days 30 -in root.csr -signkey rootkey.pem -set_serial 86324 -extfile openssl.root.cnf -out root.pem

openssl genpkey -algorithm RSA -out key.pem -pkeyopt rsa_keygen_bits:2048
openssl req -new -key key.pem -days 30 -extensions v3_req -batch -out request.csr -utf8 -subj '/CN=*'
# subl openssl.ss.cnf
openssl x509 -req -sha256 -days 30 -in request.csr -CAkey rootkey.pem -CA root.pem -set_serial 86324346454234345 -out cert.pem -extfile openssl.ss.cnf
