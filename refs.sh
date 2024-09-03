#!/bin/bash

ostree init --repo=flathub --mode bare-user-only
ostree --repo=flathub remote add --if-not-exists --no-sign-verify flathub https://dl.flathub.org/repo/

ostree --repo=flathub remote refs flathub > refs.list

grep '\.Platform/x86_64' refs.list | while read -r ref 
do
    echo pull "$ref"
    ostree --repo=flathub pull "$ref"
done