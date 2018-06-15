# Pré-requis

Avant d'arriver au workshop, les participants devront avoir préparé leurs
postes de travail afin de disposer de:

* libvirtd
* virt-manager
* 3 VM sous CentOS 7
* authentification SSH VM -> user@hyperviseur
* les VM se ping entre elles

## Préparation des VM

* échanger les clés SSH entre root sur les VM et le user de l'hyperviseur
  
  ~~~
  ssh-keygen
  ssh-copy-id <user>@<ip hyperviseur>
  ~~~

* les VM devraient pouvoir communiquer entre elles via les noms des noeuds,
  par exemple : 
  
  ~~~
  cat >> /etc/hosts <<EOF
  192.168.122.101 hanode1
  192.168.122.102 hanode2
  192.168.122.103 hanode3
  192.168.122.110 ha-vip
  EOF
  ~~~

## Firewall

* authoriser postgresql et les services de hautes dispo
  
  ~~~
  firewall-cmd --permanent --add-service=high-availability
  firewall-cmd --permanent --add-service=postgresql
  firewall-cmd --reload
  ~~~

## Dossier temporaire

* sur chaque serveur, créer le dossier /tmp/sub

  ~~~
  mkdir /tmp/sub
  ~~~
