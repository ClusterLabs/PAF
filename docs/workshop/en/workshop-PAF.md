---
subtitle : 'Workshop Pacemaker/PostgreSQL'
title : 'An introduction to PostgreSQL Automatic Failover'

licence : PostgreSQL
author: Jehan-Guillaume de Rorthais, Maël Rimbault, Adrien Nayrat, Stefan Fercot, Benoit Lobréau
revision: 0.2
url : http://clusterlabs.github.io/PAF/

#
# PDF options
#

colorlinks: true
toc: true
geometry:
- top=20mm
- left=20mm
- right=20mm
- bottom=15mm
papersize: a4

#
# Reveal Options
#

theme: white
transition: None
transition-speed: fast
progress: true
slideNumber: true
history: true
mouseWheel: true
title-transform : none
hide_author_in_slide: true

---

# Introduction

-----

## Minimum prerequisites

FR * fiabilité des ressources (matériel, réseau, etc.)
FR * redondance de chaque élément d'architecture
FR * synchronisation des horloges des serveurs
FR * supervision de l'ensemble

* ressource fiability (hardware, network, etc.)
* redundancy of each element of the architecture
* syncronization of the server clocks
* supervising everything

::: notes

FR La résistance d'une chaîne repose sur son maillon le plus faible.
FR
The resiliance of a chain is based on the resiliance of it's weakest link.

FR Un pré-requis à une architecture de haute disponibilité est d'utiliser du
FR matériel de qualité, fiable, éprouvé, maîtrisé et répandu.  Fonder son
FR architecture sur une technologie peu connue et non maîtrisée est la recette
FR parfaite pour une erreur humaine et une indisponibilité prolongée.
FR
One prerequisite for an high availability architecture is to use quality
hardware i.e. reliable, tested, mastered and wide spread. Building an
architecture on a lesser known technology that is not mastered is the recipe
for human errors and prolongued periods of downtime.

FR De même, chaque élément doit être redondé.  La loi de Murphy énonce que « tout
FR ce qui peut mal tourner, tournera mal ».  Cette loi se vérifie très
FR fréquemment.  Les incidents se manifestent rarement là où on ne les attend le
FR plus.  Il faut réellement tout redonder :
FR
Likewise, each element must have it's replacement. Murphy's Law states that "if
something can go wrong, it will". This law is very ofter proven true.  Problems
rarely arise where we await them the most. Everything in the architectyre must
have some redundancy:

FR * chaque application ou service doit avoir une procédure de bascule
FR * CPU (multi-socket), mémoire (multi-slot, ECC), disques (niveaux de RAID)
FR * redondance du SAN
FR * plusieurs alimentations électriques par serveur, plusieurs sources
FR   d'alimentation
FR * plusieurs équipements réseaux, liens réseaux redondés, cartes réseaux, WAN et
FR   LAN
FR * climatisation redondée
FR * plusieurs équipements de fencing (et chemins pour accéder)
FR * plusieurs administrateurs comprenant et maîtrisant chaque brique du cluster
FR * ...
FR
* each application or sevice must have a failover procedure
* CPU (multi-socket), memory (multi-slotn ECC, disks (RAID levels)
* SAN 
* several power supply per server with different origins
* several network hardware, network links, network cards, WAN & LAN
* air conditioning
* several fencing methods (with different access paths)
* several administrators with a good understanding of the architecture
* ...

FR S'il reste un seul _Single Point of Failure_, ou _SPoF_, dans l'architecture,
FR ce point subira un jour une défaillance.
FR
If there is one _Single Point of Failure_, or _SPoF_,  in the architecture,
it will fail one day or another.

FR Concernant le synchronisme des horloges des serveurs entre eux, celui-ci est
FR important pour les besoins applicatifs et la qualité des données.  Suite à une
FR bascule, les dates pourraient être incohérentes entre celles écrites par la
FR précédente instance primaire et la nouvelle.
FR
It is paramount that all server clocks are synchronized for the applications
and their data to be safe. For example: after a failover of a database,
inconsistancies must be avoided between the dates provided by the old primary
databse and the new one.

FR Ensuite, ce synchronisme est important pour assurer une cohérence dans
FR l'horodatage des journaux applicatifs entre les serveurs.  La compréhension
FR rapide et efficace d'un incident dépend directement de ce point.  À noter qu'il
FR est aussi possible de centraliser les logs sur une architecture dédiée à part
FR (attention aux _SPoF_ ici aussi).
FR
This synchronization is also important to have coherent timestamps in the
application logs across all servers. This is very important to understand and
fix problems in a quick and reliable way. It's also possible to centralize logs
in a dedicated architecture. In that case, be careful that it doesn't become
another SPOF.

FR Le synchronisme des horloges est d'autant plus important dans les
FR environnements virtualisés où les horloges ont facilement tendance à dévier.
FR
Finally, clock synchronization is very important in virtualized environnemnt
where clock can easily drift.

:::

-----

## _Fencing_

FR * difficulté de déterminer l'origine d'un incident de façon logicielle
FR * chaque brique doit toujours être dans un état déterminé
FR * garantie de pouvoir sortir du système un élément défaillant
FR * implémenté dans Pacemaker au travers du _daemon_ `stonithd`
FR
* complexity to diagnose the origin of a problem with software
* each element must be in a defined state
* guaranty to be able to exclude a failing element from the system
* implemented in Pacemaker by the daemon `stonithd`

::: notes

FR Lorsqu'un serveur n'est plus accessible au sein d'un cluster, il est impossible
FR aux autres nœuds de déterminer l'état réel de ce dernier.  A-t-il crashé ?
FR Est-ce un problème réseau ?  Subit-il une forte charge temporaire ?
FR
When a server is not accessible from the rest of the cluster, it's not possible
for the other server to determine it's real state. Did it crash ? Was it a
network problem ? Is it temporarily under stress ?

FR Le seul moyen de répondre à ces questions est d'éteindre ou d'isoler le serveur
FR fantôme d'autorité.  Cette action permet de déterminer de façon certaine son
FR statut : le serveur est hors _cluster_ et ne reviendra pas sans action humaine.
FR
The only way to answer these questions is to shutdown or isolate the ghost
server. After this action, we are sure of the state of the server and we
know it cannot come back into the cluster without human intevention.

FR Une fois cette décision prise et appliquée avec succès, le _cluster_ peut
FR mettre en œuvre les actions nécessaires pour rendre les services en HA de
FR nouveau disponibles.
FR
Once this decision to fence a server is taken and applied, the cluster can take
some actions to make sure the HA services are available.

FR Passer outre ce mécanisme, c'est s'exposer de façon certaine à des situations
FR dites de _split brain_, où plusieurs sous-partitions du _cluster_ initial
FR continuent à fonctionner de façon autonomes.
FR
Disregarding this safety mecanism will expose the system to _split brain_
issues, where several partitions of the cluster continue to operate on their
own.

FR Par exemple, si le _cluster_ contient des ressources de bases de données en
FR réplication avec une seule instance primaire, le _split brain_ indique que
FR plusieurs instances sont accessibles simultanément en écriture au sein du
FR _cluster_, mais ne répliquent pas entre elles.  Réconcilier les données de ces
FR deux instances peut devenir un véritable calvaire et provoquer une ou plusieurs
FR indisponibilités.  Voici un exemple réel d'incident de ce type :
Fr <https://blog.github.com/2018-10-30-oct21-post-incident-analysis/>.  Ici, une
FR certaine quantité de données n'a pas été répliquée de l'ancien primaire vers le
FR nouveau avant la bascule.  En conséquence, plusieurs jours ont été nécessaires
FR afin de réintégrer et réconcilier les données dans le _cluster_ fraîchement
FR reconstruit.
FR
In the specific case where the cluster is managing databases with a replication
setup, a _split brain_ scenario would entail several instances of the database
available in read/write mode at the sametime without any form of replication
active. Fixing the data from theses database will be complicated and time
consuming, which could lead to one or more downtime periods. Here is a real
life example of that kind of incident:
<https://blog.github.com/2018-10-30-oct21-post-incident-analysis/>. In this
case some data has not been replicated from the old primary to the new one
before the switchover. As a result, several days were needed to restore the
lost data in the newly build cluster.

FR Ne sous-estimez jamais le pouvoir d'innovation en terme d'incident des briques
FR de votre _cluster_ pour provoquer une partition des nœuds entre eux.  En voici
FR quelques exemples : <https://aphyr.com/posts/288-the-network-is-reliable>
FR
Never underestimate the inovative nature of incidents, and the likelihood that
they will provoque a parition in your cluster. Here are some more examples:
<https://aphyr.com/posts/288-the-network-is-reliable>.

FR À noter que PAF est pensé et construit pour les _clusters_ configurés avec le
FR _fencing_.  En cas d'incident, il y a de fortes chances qu'une bascule n'ait
FR jamais lieu pour un _cluster_ dépourvu de _fencing_.
FR
Please note that PAF is build with fencing enabled clusters in mind. In case of
incident, a failover might not occur if your cluster is not equipped with the
relevant fencing ressources.

:::

-----

## Quorum

FR * quelle partie du cluster doit fonctionner en cas de partition réseau ?
FR  * un vote à chaque élément du _cluster_
FR  * le _cluster_ ne fonctionne que s'il a la majorité des votes
FR
* which part of the cluster should keep operating in case of network partition
  ?
  * one vote per cluster member
  * the cluster keeps running only if it has the majority of the votes

::: notes

FR Le quorum est le nombre minimum de votes qu'une transaction distribuée doit
FR obtenir pour être autorisée à effectuer une opération dans le système.  Son
FR objectif est d'assurer la cohérence du système distribué.
FR
The quorum is the minimum number of votes requiered for a distributed
transaction to be authorized to execute an opération on the system. It's goal
is to guaranty the coherence of the distributed system.

FR Pour ce faire, chaque nœud du système se voit assigner un nombre de votes.  Il
FR faut au moins que `(N / 2) + 1` votes soient présents pour que le quorum soit
FR atteint, avec `N` le nombre de votes possible.  Le _cluster_ ne fonctionne que
FR si la majorité des nœuds sont présents.
FR
To archive this goal, each node is granted some votes. A minimum of `(N / 2) +
1` votes are requiered for the quorum to be archived (`N` being the maximum number
of vote possible). The cluster will be able to operate only if the majority
is archived.

FR Suite à une partition réseau, le quorum permet au cluster de savoir quelle
FR partition doit conserver les services actifs, celle(s) où il doit les
FR interrompre, et qui peut déclencher des opérations de fencing si nécessaire.
FR
After a network partition, the cluster uses the quorum information to know
which partition must keep the services active, and which partition must stop
all the services. Fencing operation can be started if necessary. 

FR En plus d'arrêter ses services locaux, une partition du cluster n'atteignant
FR pas le quorum ne peut notamment pas actionner le fencing des nœuds de la
FR partition distante.
FR
FR Ce mécanisme est donc indispensable au bon fonctionnement du cluster.
FR
In addition to stopping local services, a cluster partition who doesn't meet
the quorum cannot use fencing on the node of the other partition.

<!-- TODO: test this !! -->

This mecanism is paramount for the cluster to operate correctly.

:::

-----

## KISS

FR * une architecture complexe pose des problèmes
FR   * de mise en œuvre (risque de _SPOF_)
FR   * de maintenance
FR   * de documentation
FR * il est préférable de toujours aller au plus simple
FR
* complex architechture pose complex problems
  * to build (avoid a _SPOF_)
  * to maintain
  * to document
* it's advised to aim for simplicity first and foremost


::: notes

FR Augmenter la complexité d'un cluster augmente aussi le nombre de défaillances possibles. Entre deux solutions, la
FR solution la plus simple sera souvent la meilleure et la plus pérenne.
FR
FR L'incident décrit par de Gocardless dans le lien ci-après est un bon exemple. L'article indique que l'automatisation
FR réduit la connaissance de l'architecture. Au fil du temps il est difficile de maintenir une documentation à jour, des
FR équipes correctement formées :
FR
Increasing the complexity of a cluster also increases the number of failures
scenarios. Given two cluster implementations, the simplest one will usually be
the best and most sustainable.

The outage described by Grocardless in the following hyperlink is a good
example of this. The article describes how automation erodes the knowledge of
the architecture and how it's difficult ot keep the documentation up to date
and the team trained:

[Incident review: API and Dashboard outage on 10 October
2017](https://gocardless.com/blog/incident-review-api-and-dashboard-outage-on-10th-october/)

> **Automation erodes knowledge**
>
> It turns out that when your automation successfully handles failures for two
years, your skills in manually controlling the infrastructure below it atrophy.
There's no "one size fits all" here. It's easy to say "just write a runbook",
but if multiple years go by before you next need it, it's almost guaranteed to
be out-of-date.

:::

-----

## History

-----

### History of Pacemaker

FR * plusieurs plate-formes historiques distinctes
FR   * projet Linux-HA mené par SUSE
FR   * "Cluster Services" de Red Hat
FR * 2007 : Pacemaker apparaît
FR   * issu de Linux-HA
FR   * 1er point de convergence
FR
* several projects on different platforms 
  * Linux HA project led by SUSE
  * "Cluster Services" by Red Hat
* 2007: Pacemaker 
  * originated from Linux-HA
  * first convergence

::: notes

FR Un historique complet est disponible
FR [ici](https://www.alteeve.com/w/High-Availability_Clustering_in_the_Open_Source_Ecosystem).
FR
FR Plusieurs sociétés se sont forgées une longue expérience dans le domaine de la Haute Disponibilité en maintenant chacun
FR leur plate-forme.
FR
FR SUSE d'abord, avec son projet Linux-HA. Red Hat ensuite avec "Cluster Services".
FR
FR En 2007, issu d'une première collaboration, Pacemaker apparaît pour gérer les clusters peu importe la couche de
FR communication utilisée : OpenAIS (Red Hat) ou Heartbeat (SUSE).
FR
The complete history is available 
[here](https://www.alteeve.com/w/High-Availability_Clustering_in_the_Open_Source_Ecosystem).

Several companies have build a long standing experience in the field of high
availability and provide solution dedicated to it.

SUSE is one of them with the project Linux-HA. Red Hat is also known for their
"Cluster Services".

In 2007, a first collaborative work leads to the birth of Pacemaker. This
solution is designed to operate clusters over the different communication
layers avaiable at that time: OpenAIS (Reh Hat) or Heartbeat (SUSE).

:::

-----

### Historique de Pacemaker - suite

FR * 2009 : Corosync apparaît
FR   * issu de OpenAIS
FR   * 2ème point de convergence
FR * 2014 : début de l'harmonisation
FR
* 2009 : Corosync
  * based on OpenAIS
  * 2nd convergence
* 2014 : the harmonisation starts

::: notes

FR En 2009 apparaît l'uniformisation des couches de communication grâce à Corosync.
FR
FR Une collaboration forte étant désormais née, Pacemaker et Corosync deviennent petit à petit la référence et chaque
FR distribution tend vers cette plate-forme commune.
FR
In 2009, an effort to standarize the communication layers leads the birth of
Corosync.

A strong collaboration is born, Pacemaker and Corosync are becoming the
reference for Linux high availability and all the Linux distributions start to
include these tools in their packaging.

:::

-----

### History of Pacemaker - future

FR * 2017: les principales distributions ont convergé
FR   * Corosync 2.x et Pacemaker 1.1.x
FR * 2018: corosync 3 et Pacemaker 2.0.x
FR
* 2017: the main distribution have converged
  * Corosync 2.x and Pacemaker 1.1.x
* 2018: corosync 3 and Pacemaker 2.0.x

::: notes

FR En 2017, les dernières versions des principales distributions Linux avaient toutes fini leur convergence vers Corosync
FR 2.x et Pacemaker 1.1.x. Seul le client d'administration de haut niveau varie en fonction de la politique de la
FR distribution.
FR
In 2017, the latest versions of the main Linux distributions are done
converging to Corosync 2.x and Pacemaker 1.1.x. The last divergence lies with
the administration client.

FR Début 2018, Pacemaker 2.0 et Corosync 3.0 font leur apparition. Coté Pacemaker, les principaux changements concernent:
FR
FR * la suppression de beaucoup de code consacré aux anciennes architectures devenues obsolètes : incompatibilité avec
FR   OpenAIS, CMAN, Corosync 1.x, Heartbeat
FR * plusieurs paramètres de configuration ont été supprimés ou remplacés par des équivalents pour une configuration plus
FR   cohérente
FR
FR Pour plus de détails, voir: <https://wiki.clusterlabs.org/wiki/Pacemaker_2.0_Changes>
FR
A the beginning of 2018, Pacemaker 2.0 and Corosync 3.0 are release. One the
Pacemaker side, the main changes are :

* the removal of a lot of code dedicated to old architectures: OpenAIS, CMAN,
  Corosync 1.x and Heartbeat compatibility is dropped.
* several configuration parameters have been removed or replaced with others in
  an effort to make the configuration more consistent.

More information is available here: <https://wiki.clusterlabs.org/wiki/Pacemaker_2.0_Changes>

FR Concernant Corosync, la principale nouveauté est le support du projet "Kronosnet" comme protocole de communication au
FR sein du cluster. Cette librairie permet d'ajouter beaucoup de souplesse, de fonctionnalités, de visibilité sur
FR l'activité de Corosync et surtout une latence plus faible que l'actuel protocole. Entre autre nouveautés, nous
FR trouvons :
FR
FR * le support de un à huit liens réseaux
FR * l'ajout de liens réseaux à chaud
FR * le mélange de protocoles entre les liens si nécessaire
FR * plusieurs algorithmes de gestions de ces liens (active/passive ou active/active)
FR * la capacité de gérer la compression et/ou le chiffrement
FR
FR Pour plus de détails, voir: [Kronosnet:The new face of Corosync communications](http://build.clusterlabs.org/corosync/presentations/2017-Kronosnet-The-new-face-of-corosync-communications.pdf)
FR
As far as Corosync is concerned, the main novelty is the support for the
project "Kronosnet" as the communication protocol. This library allows for more
flexibility, adds more fonctionalities, facilitates the supervision of Corosync
and decreases the latency. Some of the novelties are listed below :

* support for up to 8 network links
* support for the addition of network without restart
* support for multiple protocols in different links
* several algorithm to manage links (active/passive or active/active)
* support for compression and encryption

More information is available here: [Kronosnet:The new face of Corosync communications](http://build.clusterlabs.org/corosync/presentations/2017-Kronosnet-The-new-face-of-corosync-communications.pdf)

:::

-----

## Administration clients

FR * `crmsh`
FR   * outil originel
FR   * gestion et configuration du cluster
FR * `pcs`
FR   * introduit par Red Hat
FR   * supporte également Corosync
FR   * utilisé dans ce workshop
FR
* `crmsh`
  * original tool
  * management and configuration of the cluster
* `pcs`
  * introduced by Red Hat
  * also supports Corosync
  * used in this workshop

::: notes

FR A l'origine du projet Pacemaker, un outil apparaît : `crmsh`. Cet outil permet de configurer et de gérer le cluster
FR sans toucher aux fichiers de configuration. Il est principalement maintenu par Suse et présente parfois des
FR incompatibilités avec les autres distributions pour la création du cluster lui-même, son démarrage ou son arrêt.
FR Néanmoins, l'outil évolue très vite et plusieurs de ces incompatibilités sont corrigées.
FR
The tool `cmrsh` originates to the beginning of the Pacemaker project. This
tool is designed to managed and configure the cluster without requiering to
modify the configuration files. It's mostly maintained by SUSE, and sometimes
presents incompatibilities with other distribution in the creation, starting
and stopping process of the cluster. Nevertheless, the tool evolves quickly and
several incompatibilities hav been fixed.

FR Lorsque Red Hat intègre Pacemaker, un nouvel outil est créé : `pcs`. En plus de regrouper les commandes de Pacemaker,
FR il supporte également Corosync (et CMAN pour les versions EL 6) et inclut un service HTTP permettant (entre autre) la
FR configuration et la maintenance du cluster via un navigateur web.
FR
When Red Hat adopted Pacemaker, a new tool was created: `pcs`. It regroups all
the Pacemaker commands along with those for Corosync (and CMAN in the versions
for EL 6). It includes an HTTP service to configure and maintain the cluster
via a web browser.

FR Concernant le contrôle du cluster, `crmsh` repose sur SSH et csync2 pour l'exécution de commandes sur les serveurs
FR distants (via la librairie python `parallax`) et la gestion de la configuration sur tous les serveurs.
FR
`crmsh` uses SSH and csync2 to execute commands on the remote servers (via the
`parallax` python library) and manage the configuration across all servers.

FR Pour ces mêmes tâches, les daemons `pcsd` échangent des commandes entre eux via leur service web. Le daemon `pcsd` gère
FR à la fois une API HTTP pour la communication de commandes inter-serveurs ou l'interface HTTP à destination de
FR l'administrateur.
FR
FR Lorsqu'une commande nécessite une action côté système (donc hors Pacemaker), les daemon `pcsd` communiquent entre eux
FR et s'échangent les commandes à exécuter localement au travers de cette API HTTP. Les commandes sollicitant cette API
FR peuvent être la création du cluster lui-même, son démarrage, son arrêt, sa destruction, l'ajout ou la suppression d'un
FR nœud, etc.
FR
To archive the same tasks, the `pcsd` daemons exchange commands via their web
services. The `pcsd` daemon manages the communication for the HTTP API
dedicated to inter-server commands and the administration.

When a command requiers a system operation (outside of Pacemaker), the `pcsd`
daemons communicate and exchange the commands to execute using the HTTP API.
The command that use this API range from the cluster creation or destruction,
starting or stopping process and the addition or removal a node, etc. 

FR En 2018, `pcs` a fini d'être intégré à Debian. `crmsh` est encore utilisé en priorité sous Suse, mais reste souvent
FR utilisé sur les Debian et Ubuntu par choix historique et reste un très bon choix, pour peu que l'administrateur ne
FR l'utilise pas pour interagir avec le système lui même.
FR
In 2018, `pcs` is fully integrated into Debian. `crmsh` is still used in
piority in SUSE, it's also often used in Debian and Ubuntu since it's the
historic choice for thoses platforms. It remains a good choise as long as the
administrator doesn't need to interact with the system.

FR **Ce workshop se base sur une distribution CentOS 7 et sur l'outil `pcs`**.
FR
**This workshop is based on Centos 7 and uses the `pcs` tool.**

:::

-----

## Available versions

* RHEL 7 and Debian 9:
  * Corosync 2.x
  * Pacemaker 1.1.x

* RHEL 8 and Debian 10:
  * Corosync 3.x
  * Pacemaker 2.0.x


::: notes

FR L'installation recommandée (et supportée) suivant les distributions de RHEL et dérivés :
FR
The recommanded (and supported ) version depending on the distribution are:

| OS        | Corosync | Pacemaker | Administration               |
|:---------:|:--------:|:---------:|------------------------------|
| EL 7      | 2.x      | 1.1.x     | pcsd 0.9                     |
| EL 8      | 3.x      | 2.0.x     | pcsd 0.10                    |
| Debian 8  | 1.4      | 1.1.x     | crmsh                        |
| Debian 9  | 2.4      | 1.1.x     | pcs 0.9 ou crmsh 2.3         |
| Debian 10 | 3.0      | 2.0.x     | pcs 0.10 ou crmsh 4.0        |

FR L'équipe de maintenance des paquets Pacemaker n'a pu intégrer les dernières
FR versions des composants à temps pour la version 8 de Debian. Il a été décidé
FR d'utiliser officiellement le dépôt backport de Debian pour distribuer ces
FR paquets dans Debian 8. Les versions 8 et 9 de Debian partagent donc les mêmes
FR versions des paquets concernant Pacemaker.
FR
The maintenace team in charge of the Pacemaker packaging couldn't include the
last versions of it's components in time for version 8 of Debian. It was
decided to use the debian backport repository to distribute thoses packages in
Debian 8. Therefore the version 8 and 9 of Debian share the same package
versions regarding Pacemaker.

FR L'initialisation du cluster avec `crmsh` 2.x n'est toujours pas fonctionnelle
FR et ne devrait pas être corrigée, la branche 3.x étant désormais la branche
FR principale du projet. La version 3.0 de `crmsh` supporte l'initialisation d'un
FR cluster sous Debian mais avec un peu d'aide manuelle et quelques erreurs
FR d'intégration.
FR
The initialisation of the cluster with `crmsh` 2.x is still not working but
should be fixed, the 3.x branch of the project is now it's main branch. The 3.0
version of `crmsh` supports the cluster initialisation with some manual
intervention and intergration errors.

FR L'utilisation de `pcsd` et `pcs` est désormais pleinement fonctionne sous
FR Debian. Voir à ce propos:
FR <https://clusterlabs.github.io/PAF/Quick_Start-Debian-9-pcs.html>
FR
The use of `pcsd` and `pcs` is now full operationnal in Debian. See: 
<https://clusterlabs.github.io/PAF/Quick_Start-Debian-9-pcs.html>

:::

-----

# First steps with Pacemaker

FR Ce chapitre aborde l'installation et démarrage de Pacemaker. L'objectif est de
FR créer rapidement un cluster vide que nous pourrons étudier plus en détail
FR dans la suite du workshop.
FR
This chapter takes up the installation and start-up of Pacemaker. The objective
is to quickly create an empty cluster that we will be using in the rest of this
workshop.

-----

## Installation

FR Paquets essentiels:
FR
FR * `corosync` : communication entre les nœuds
FR * `pacemaker` : orchestration du cluster
FR * `pcs` : administration du cluster
FR
Important packages:

* `corosync`: messaging layer
* `pacemaker`: cluster orchestration
* `pcs`: administration of the cluster

:::notes

FR L'installation de Pacemaker se fait très simplement depuis les dépôts
FR officiels de CentOS 7 en utilisant les paquets `pacemaker`. notez que
FR les paquets `corosync` et `resource-agents` sont installés aussi par dépendance.
FR
FR Voici le détail de ces paquets :
FR
FR * `corosync` : gère la communication entre les nœuds, la gestion du groupe, du quorum
FR * `pacemaker` : orchestration du cluster, réaction aux événements, prise de
FR   décision et actions
FR * `resource-agents`: collection de _resource agents_ (_RA_) pour divers services
FR
The installation of Pacemaker is made simple by using the `pacemaker` package
available from the CentOS 7 official repositories. Please note that the
`corosync` and the `resource-agents` packages are also installed as
dependencies.

More details about the packages:

* `corosync`: manages the communication between nodes, the cluster and the
  quorum
* `pacemaker`: orchestrates the cluster, reacts to events, makes decisions an
  performs actions
* `resource-agents` (_RA_): are a collection of scripts that share a comon API
  and allow Pacemaker to control and monitor different kind of resources.

FR Le paquet `corosync` installe un certain nombre d'outils commun à toutes les
FR distributions et que nous aborderons plus loin:
FR
The `corosync` package installs several tools common to all Linux
distributions. We will describe them later on:

* `corosync-cfgtool`
* `corosync-cmapctl`
* `corosync-cpgtool`
* `corosync-keygen`
* `corosync-quorumtool`

FR Pacemaker aussi installe un certain nombre de binaires commun à toutes les
FR distributions, dont les suivants que vous pourriez rencontrer dans ce workshop
FR ou dans certaines discussions :
FR
Pacemaker also installs it's share of binaries that are common across all Linux
distributions. Some of them are listed below as they will be used in the rest
of this workshop or are commonly discussed in Pacemaler related topics:

* `crm_attribute`
* `crm_node`
* `attrd_updater`
* `cibadmin`
* `crm_mon`
* `crm_report`
* `crm_resource`
* `crm_shadow`
* `crm_simulate`
* `crm_verify`
* `stonith_admin`

FR Beaucoup d'autres outils sont installés sur toutes les distributions, mais sont
FR destinés à des utilisations très pointues, de debug ou aux agents eux-même.
FR
A lots of other tools are installed on all distributions, but their use cases
are limited to some debug activities or used only by the agents.

FR Les outils d'administration `pcs` et `crm` reposent fortement sur l'ensemble de
FR ces binaires et permettent d'utiliser une interface unifiée et commune à
FR ceux-ci. Bien que l'administration du cluster peut se faire entièrement sans
FR ces outils, ils sont très pratiques au quotidien et facilitent grandement la
FR gestion du cluster. De plus, ils intègrent toutes les bonnes pratiques
FR relatives aux commandes supportées.
FR
The administration tools `pcs` and `crm` build upon these tools and create a
unified interface to manage the cluster. Even thought cluster admnistration
tasks can be performed without these tools, they are very usefull and ease
cluster management to a great degree. Moreover, they apply all the best
practices for the supported commands.

FR Tout au long de cette formation, nous utilisons le couple `pcs` afin de
FR simplifier le déploiement et l'administration du cluster Pacemaker. Il est
FR disponible sur la plupart des distributions Linux et se comportent de la même
FR façon, notamment sur Debian et EL et leurs dérivés.
FR
<!-- FIXME "le couple" sans rien après -->

During this workshop, we will be using pcs to simplify the deployement and the
administration of the cluster. In addition to it's simplicity, the tool works
the same on all Linux distributions, most notably Debian, EL and their
derivatives.

FR Ce paquet installe le CLI `pcs` et le daemon `pcsd`. Ce dernier s'occupe
FR seulement de propager les configurations et commandes sur tous les nœuds.
FR
The packages install both the CLI `pcs` and the daemon `pcsd`. The latter is
responsible for the propagation of the configuration and commands across nodes.

:::

-----

### Practical work: Installation of Pacemaker

::: notes

FR 1. installer les paquets nécessaires et suffisants
FR 2. vérifier les dépendances installées
FR
1. install the required packages
2. verify which dependencies were installed

:::

-----

### Correction: Installation of Pacemaker

::: notes

FR 1. Installer les paquets nécessaires et suffisants
FR
1. Install the required packages

~~~console
# yum install -y pacemaker
~~~

FR 2. vérifier les dépendances installées
FR
FR À la fin de la commande précédente:
FR
2. verify which dependencies were installed

After the execution of the previous command:

~~~
Dependency Installed:
[...]
  corosync.x86_64 0:2.4.3-6.el7_7.1
  pacemaker-cli.x86_64 0:1.1.20-5.el7_7.2
  resource-agents.x86_64 0:4.1.1-30.el7_7.4
~~~

FR Les paquets `corosync`, `resource-agents` et `pacemaker-cli` ont été installés en tant que
FR dépendance de `pacemaker`.
FR
FR Tous les outils nécessaires et suffisants à l'administration d'un cluster
FR Pacemaker sont présents. Notamment:
FR
The packages `corosync`, `resource-agents` and `pacemaker-cli` have been
installed as dependencies of `pacemaker`.

All the requiered tools for the administration of a Pacemaker cluster are
present. In particular:

~~~console
# ls /sbin/crm* /sbin/corosync*

/sbin/corosync            /sbin/corosync-cfgtool /sbin/corosync-cmapctl
/sbin/corosync-cpgtool    /sbin/corosync-keygen  /sbin/corosync-notifyd
/sbin/corosync-quorumtool

/sbin/crmadmin            /sbin/crm_attribute    /sbin/crm_diff
/sbin/crm_error           /sbin/crm_failcount    /sbin/crm_master
/sbin/crm_mon             /sbin/crm_node         /sbin/crm_report
/sbin/crm_resource        /sbin/crm_shadow       /sbin/crm_simulate
/sbin/crm_standby         /sbin/crm_ticket       /sbin/crm_verify
~~~

:::

-----

### Practical work: Installation of `pcs`

::: notes

FR 1. installer le paquet `pcs`
FR 2. activer le daemon `pcsd` au démarrage de l'instance et le démarrer
FR
<!-- FIXME: du serveur ? -->

1. install the `pcs` package
2. enable the `pcsd` daemon so that it starts when the server boots, then start
   it.

:::
-----

### Correction: Installation of `pcs`

::: notes

FR 1. installer le paquet `pcs`
FR
1. install the `pcs` package

~~~console
# yum install -y pcs
~~~

FR 2. activer `pcsd` au démarrage de l'instance et le démarrer
FR
2. enable the `pcsd` daemon so that it starts when the server boots, then start
   it.

~~~console
# systemctl enable --now pcsd
~~~

or

~~~console
# systemctl enable pcsd
# systemctl start pcsd
~~~

:::

-----

## Cluster creation

FR * authentification des daemons `pcsd` entre eux
FR * création du cluster à l'aide de `pcs`
FR   - crée la configuration corosync sur tous les serveurs
FR * configuration de Pacemaker des _processus_ de Pacemaker
FR
<!-- FIXME y a des mots en trop -->

* authenticate all `pcsd` daemons among each other
* create the cluster with `pcs`
   - creates the corosync configuration on all servers
* configures the behavior of Pacemaker's processes

::: notes

FR La création du cluster se résume à créer le fichier de configuration de
FR Corosync, puis à démarrer de Pacemaker.
FR
Cluster creation is done by creating the relevant configuration file for
Corosync and starting Pacemaker.

FR L'utilisation de `pcs` nous permet de ne pas avoir à éditer la configuration de
FR Corosync manuellement. Néanmoins, un pré-requis à l'utilisation de `pcs` est
FR que tous les daemons soient authentifiés les uns auprès des autres pour
FR s'échanger des commandes au travers de leur API HTTP. Cela se fait grâce à la
FR commande `pcs cluster auth [...]`.
FR
Using `pcs` simplifies this process since it does the configuration file
creation for you. However, it's necessary that all `pcsd` dameon are
authenticated among each other to enable the exchange of commands using the
HTTP API. This can be done with the command `pcs cluster auth [...]`.

FR Il est ensuite aisé de créer le cluster grâce à la commande `pcs cluster
FR setup [...]`.
FR
Once this is done, it's easy to create the cluster using `pcs cluster setup
[...]`.

FR Le fichier de configuration de Pacemaker ne concerne que le comportement des
FR processus, pas la gestion du cluster. Notamment, où sont les journaux
FR applicatifs et leur contenu. Pour la famille des distributions EL, son
FR emplacement est `/etc/sysconfig/pacemaker`. Pour la famille des distributions
FR Debian, il sont emplacement est `/etc/default/pacemaker`. Ce fichier en
FR concerne QUE l'instance locale de Pacemaker. Chaque instance peut avoir un
FR paramétrage différent, mais cela est bien entendu déconseillé.
FR

The Pacemaker configuration file deals with the behavior of Pacemaker's
processes, not the cluster management. Information such as where are the traces
and what is logged can be found there. On the EL familly, the file is stored in
the `/etc/sysconfig/pacemaker` directory. On Debian, it's located in
`/etc/default/pacemaker`. This file is relevant only for the local instance of
Pacemaker. Each node can have a different configuration, but this practice is
discouraged.

:::

-----

### Practical work: pcs authentication

::: notes

FR 1. positionner un mot de passe pour l'utilisateur `hacluster` sur chaque nœud
FR
FR L'outil `pcs` se sert de l'utilisateur système `hacluster` pour s'authentifier
FR auprès de `pcsd`. Puisque les commandes de gestion du cluster peuvent être
FR exécutées depuis n'importe quel membre du cluster, il est recommandé de
FR configurer le même mot de passe pour cet utilisateur sur tous les nœuds pour
FR éviter les confusions.
FR
1. create a password for the `hacluster` user on each node.

The `pcs` tool uses the `hacluster` system user for the authentication with
`pcsd`.  Since the cluster management commands can be executed for any member
of the cluster, it is advised to configure the same password on all node to
avoid mixing them up.


FR 2. authentifier les membres du cluster entre eux
FR
FR Remarque: à partir de Pacemaker 2, cette commande doit être exécutée sur chaque
FR nœud du cluster.
FR
2. authenticate all cluster members among each other

Note: since Pacemaker 2, the command must be executed on each node of the
cluster.

:::

-----

### Correction: pcs authentiation

::: notes

FR 1. positionner un mot de passe pour l'utilisateur `hacluster` sur chaque nœud
FR
1. create a password for the `hacluster` user on each node.

~~~console
# passwd hacluster
~~~

FR 2. authentifier les membres du cluster entre eux
FR
2. authenticate all cluster members among each other

~~~console
# pcs cluster auth hanode1 hanode2 hanode3 -u hacluster
~~~

:::

-----

### Practical work: Cluster creation with pcs

::: notes

FR Les commandes `pcs` peuvent être exécutées depuis n'importe quel nœud.
FR
FR 1. créer un cluster nommé `cluster_tp` incluant les trois nœuds `hanode1`,
FR    `hanode2` et `hanode3`
FR 2. trouver le fichier de configuration de corosync sur les trois nœuds
FR 3. vérifier que le fichier de configuration de corosync est identique partout
FR 4. activer le mode debug de Pacemaker pour les sous processus `crmd`,
FR `pengine`, `attrd` et `lrmd`
FR
The `pcs` commands can be executed from any node.

1. create the cluster `cluster_tp` with three node `hanode1`, `hanode2` and
   `hanode3`
2. find the corosync configuration file on all three nodes
3. check that the configuration file is identical on all three nodes
4. activate the debug mode in Pacemaker for the `crmd`, `pengone`, `attrd` and
   `lrmd` sub processes.

FR Afin de pouvoir mieux étudier Pacemaker, nous activons le mode debug de des
FR sous processus `crmd`, `pengine`, `attrd` et `lrmd` que nous aborderons dans la suite de
FR cette formation.
FR
We activate the debug mode for the `crmd`, `pengine`, `attrd` and `lrmd` in
order to have an easier tume studying Pacemaker. This will be very usefull in
the rest of the workshop.

:::

-----

### Correction: Cluster creation with pcs

::: notes

FR Les commandes `pcs` peuvent être exécutées depuis n'importe quel nœud.
FR
FR 1. créer un cluster nommé `cluster_tp` incluant les trois nœuds `hanode1`,
FR    `hanode2` et `hanode3`
FR
The `pcs` commands can be executed from any node.

1. create the cluster `cluster_tp` with three node `hanode1`, `hanode2` and
   `hanode3`

~~~console
# pcs cluster setup --name cluster_tp hanode1 hanode2 hanode3
~~~

FR 2. trouver le fichier de configuration de corosync sur les trois nœuds
FR
FR Le fichier de configuration de Corosync se situe à l'emplacement
FR `/etc/corosync/corosync.conf`.
FR
2. find the corosync configuration file on all three nodes

Corosync's configuration file is located here: `/etc/corosync/corosync.conf`.

FR 3. vérifier que le fichier de configuration de corosync est identique partout
FR
3. check that the configuration file is identical on all three nodes

~~~console
root@hanode1# md5sum /etc/corosync/corosync.conf
564b9964bc03baecf42e5fa8a344e489  /etc/corosync/corosync.conf

root@hanode2# md5sum /etc/corosync/corosync.conf
564b9964bc03baecf42e5fa8a344e489  /etc/corosync/corosync.conf

root@hanode3# md5sum /etc/corosync/corosync.conf
564b9964bc03baecf42e5fa8a344e489  /etc/corosync/corosync.conf
~~~

FR 4. activer le mode debug de Pacemaker pour les sous processus `crmd`, `pengine`
FR    et `lrmd`
FR
FR Éditer la variable `PCMK_debug` dans le fichier de configuration
FR `/etc/sysconfig/pacemaker` :
FR
4. activate the debug mode in Pacemaker for the `crmd`, `pengine`, `attrd` and
   `lrmd` sub processes.

Edit the `PCMK_debug` variable in the configuration file `/etc/sysconfig/pacemaker`:

~~~console
PCMK_debug=crmd,pengine,lrmd,attrd
~~~

FR Pour obtenir l'ensemble des messages de debug de tous les processus,
FR positionner ce paramètre à `yes`.
FR


:::

-----

## Cluster startup

FR * cluster créé mais pas démarré
FR * désactiver Pacemaker au démarrage des serveurs
FR * utilisation de `pcs` pour démarrer le cluster
FR
* the cluster is created but not started
* disable Pacemaker on server startup
* use `pcs` to start the cluster

::: notes

FR Une fois le cluster créé, ce dernier n'est pas démarré automatiquement. Il est
FR déconseillé de démarrer Pacemaker automatiquement au démarrage des serveurs. En
FR cas d'incident et de fencing, un nœud toujours défaillant pourrait déstabiliser
FR le cluster et provoquer des interruptions de services suite à un retour
FR automatique prématuré. En forçant l'administrateur à devoir démarrer Pacemaker
FR manuellement, celui-ci a alors tout le loisir d'intervenir, d'analyser
FR l'origine du problème et éventuellement d'effectuer des actions correctives
FR avant de réintégrer le nœud, sain, dans le cluster.
FR
The cluster is not automatically started once it's creation. It's discouraged
to enable Pacemaker's startup at boot time. In case of outage or fencing, a
failing node could destabilize the cluster and provoque a downtime because
it joined the cluster prematurely. By forcing the administrator to start
Pacemaker manually, we give him time to intervene, analyze the origin of the
problem and conduct corrective mesure if necessary, before reintroducing the
node into the cluster.

FR Le démarrage du cluster nécessite la présence des deux services Corosync et
FR Pacemaker sur tous les nœuds. Démarrer d'abord les services Corosync puis
FR Pacemaker. À noter que démarrer Pacemaker suffit souvent sur de nombreuses
FR distributions Linux, Corosync étant démarré automatiquement comme dépendance.
FR
Cluster startup requires the presence of the Corosync and Pacemaker services on
all nodes. Corosync should be started first then Pacemaker. On most Linux
distribution, starting Pacemaker is enough, since Corosync  will be started
automatically as a dependency.

FR Plutôt que de lancer manuellement Pacemaker sur chaque nœud, il est possible
FR de sous traiter cette tâche aux daemons `pcsd` avec une unique commande `pcs`.
FR
Instead of starting Pacemaker manually on each node, it's possible to delagate
this task to the `pcsd` daemons thanks to a single `pcs` command.

:::

-----

### Practical work: Starting the cluster

::: notes

FR 1. désactiver Pacemaker et Corosync au démarrage du serveur
FR 2. démarrer Pacemaker et Corosync sur tous les nœuds à l'aide de `pcs`
FR 3. vérifier l'état de Pacemaker et Corosync
FR
1. deactivate Pacemaker and Corosync at server startup
2. start Pacemaker and Corosync on all nodes using `pcs`
3. verify the state of Pacemaker and Corosync

:::

-----

### Correction: Starting the cluster

::: notes

FR 1. désactiver Pacemaker et Corosync au démarrage du serveur
FR
FR Sur tous les serveurs:
FR
1. deactivate Pacemaker and Corosync at server startup

On all servers:

~~~console
# systemctl disable corosync pacemaker
~~~

FR Ou, depuis un seul des serveurs:
FR
Or from one of the servers:

~~~console
# pcs cluster disable --all
~~~

FR 2. démarrer Pacemaker et Corosync sur tous les nœuds à l'aide de `pcs`
FR
2. start Pacemaker and Corosync on all nodes using `pcs`

~~~console
# pcs cluster start --all
~~~

FR 3. vérifier l'état de Pacemaker et Corosync
FR
FR Sur chaque serveur, exécuter:
FR
3. verify the state of Pacemaker and Corosync

On each server, execute:

~~~
# systemctl status pacemaker corosync
~~~

Or:

~~~
# pcs status
~~~

FR Nous observons que les deux services sont désactivés au démarrage des
FR serveurs et actuellement démarrés.
FR
We can see that both services are running and have been disabled at server
startup.

:::

-----

## Visualize the cluster state

FR Pour visualiser l'état du cluster :
FR
FR * `crm_mon`: commande livrée avec Pacemaker
FR * `pcs`
FR
To visualize the cluster state:

* `crm_mon`: a command provided with Pacemaker
* `pcs`

::: notes

FR L'outil `crm_mon` permet de visualiser l'état complet du cluster et des
FR ressources. Voici le détail des arguments disponibles :
FR
FR * `-1`: affiche l'état du cluster et quitte
FR * `-n`: regroupe les ressources par nœuds
FR * `-r`: affiche les ressources non actives
FR * `-f`: affiche le nombre fail count pour chaque ressource
FR * `-t`: affiche les dates des événements
FR * `-c`: affiche les tickets du cluster (utile pour les cluster étendus sur réseau WAN)
FR * `-L`: affiche les contraintes de location négatives
FR * `-A`: affiche les attributs des nœuds
FR * `-R`: affiche plus de détails (node IDs, individual clone instances)
FR * `-D`: cache l'entête
FR
FR Voici des exemples d'utilisation:
FR
The `crm_mon` tool is geared to the visualisation of the state of the cluster
as a whole, including it's resources. Here is the detail of the available
arguments:

* `-1`: displays the state of the cluster and exits
* `-n`: gathers resources on a per node basis
* `-r`: displays the active resources
* `-f`: displays the fail count for each node
* `-t`: displays the dates of the events
* `-c`: displays the tickets of the cluster (useful for extended clusters on WAN networks)
* `-L`: displays the negative location constraints
* `-A`: displays the node attributes
* `-R`: displays mode detailed information (node IDs, individual clone instances)
* `-D`: hide the header

Here are some examples:

~~~console
# crm_mon -DnA
# crm_mon -fronA
# crm_mon -1frntcLAR
~~~

FR À noter que ces différents arguments peuvent être aussi activés ou désactivés
FR dans le mode interactif.
FR
FR L'outil `pcs` contient quelques commandes utiles pour consulter l'état d'un
FR cluster, mais n'a pas de mode interactif. Voici quelques exemples
FR d'utilisation:
FR

Please note that these arguments can also be toggle on and off in interactive
mode.

The `pcs` tool comes equiped with several commands that are useful to display
the cluster state, but it doesn't have an interactive mode. Here are few
examples of their usage:

~~~console
# pcs cluster status
# pcs status
# pcs cluster cib
# pcs constraint show
~~~

:::

-----

### Practical work: Cluster state visualization

::: notes

FR Expérimenter avec les commandes vues précédemment et leurs arguments.
FR
Experiment with the commands listed before and their arguments.

:::

-----

# Corosync

FR Rapide tour d'horizon sur Corosync.
FR
A Quick overview of Corosync.

-----

## Presentation

FR * couche de communication bas niveau du cluster
FR * créé en 2004
FR * dérivé de OpenAIS
FR * avec des morceaux de CMAN dedans ensuite (à vérifier)
FR
* communication layer of the clusterware
* created in 2004
* derived from OpenAIS
* with some components from CMAN
<!-- Vérifier le a vérifier -->

::: notes

FR Corosync est un système de communication de groupe (`GCS`). Il fournit
FR l'infrastructure nécessaire au fonctionnement du cluster en mettant à
FR disposition des APIs permettant la communication et d'adhésion des membres au
FR sein du cluster. Corosync fournit notamment des notifications de gain ou de
FR perte du quorum qui sont utilisés pour mettre en place la haute disponibilité.
FR
Corosync is a group communication system (_GCS_). It provides the
infrastructure necessary for the cluster to operate by providing API for
communication and cluster membership. Among other features, it also provides
notification for the gain or loss of quorum which is important to archive high
availability.

FR Son fichier de configuration se trouve à l'emplacement
FR `/etc/corosync/corosync.conf`. En cas de modification manuelle, il faut
FR __ABSOLUMENT__ veiller à conserver une configuration identique sur tous les
FR nœuds. Cela peut être fait manuellement ou avec la commande `pcs cluster sync`.
FR
It's configuration is located in `/etc/corosync/corosync.conf`. In case of
manual update, it is paramount to propagate the modifications on all nodes and
ensure that all nodes have the same configuration. This can be done manually
or with the command `pcs cluster sync`.

FR La configuration de corosync est décrite dans la page de manuel
FR `corosync.conf`. Ses fonctionnalités liées au quorum sont décrites dans le
FR manuel nommé `votequorum`.
FR
The Corosync configuration is described in length in the man page for
`corosync.conf`. The parameters describing quorum are described in the man page
for `votequorum`.

:::

-----

## Architecture

FR * corosync expose ses fonctionnalités sous forme de services, eg. :
FR   * `cgp` : API de gestion de groupe de processus ;
FR   * `cmap` : API de gestion de configuration ;
FR   * `votequorum` : API de gestion du quorum.
FR
* corosync exposes it's functionnalities as servises, e.g.:
  * `cpg` (closed process group): process group & membership management API;
  * `cmap`: configuration management API;
  * `votequorum`: quorum managment API.
<!-- pas sur pour cpg -->

::: notes

FR Corosync s'appuie sur une ensemble de services internes pour proposer plusieurs APIs aux applications
FR qui l'utilisent.
FR
FR Corosync expose notamment l'api `cpg` dont l'objet est d'assurer le moyen de
FR communication d'une applications distribuées. Cette api permet de gérer :
FR
FR * l'entrée et la sortie des membres dans un ou plusieurs groupes ;
FR * la propagation des messages à l'ensemble des membres des groupes ;
FR * la propagation des changements de configuration ;
FR * l'ordre de délivrance des messages.
FR
Corosync relies on a set of internal services to propose several API to its
client applications.

One of those API is `cpg` whose role is to provide means of communication for
distributed applications. This API can manage:

* the entry or exit of members in one or more groups;
* the propagation of messages to all members of said groups;
* the propagation of configuration changes;
* the order of delivery of messages.

FR Corosync utilise `cmap` pour gérer et stocker sa configuration sous forme de stockage
FR clé-valeur. Cette API est également mise à disposition des applications qui utilisent corosync.
FR Pacemaker s'en sert notamment pour récupérer certaines informations sur le cluster et
FR ses membres.
FR
Corosync uses `cmap` to manage and store it's configuration in the form of a
key value store. This API is also available for the client applications of
Corosync. For example, Pacemaker uses it to fetch some information from the
cluster and it's members.

FR Le service `votequorum` permet à corosync de fournir des notifications sur la gain ou la
FR perte du quorum dans le cluster, le nombre de vote courant, etc.
FR
The `votequorum` service is designed to provide notification when quorum is
archived or lost in the cluster, about the number of nodes in the cluster,
etc.

:::

-----

## Corosync 3 features

FR Nouvelle librairie `kronosnet` (`knet`):
FR
FR * évolution du chiffrement
FR * redondance des canaux de communications
FR * compression
FR

New library `kronosnet` (`knet`):

* cryptography
* redundancy of channels
* compression

::: notes

FR Corosync3 utilise la librairie kronosnet (`knet`). Cette libraire :
FR
FR * remplace les modes de transport `multicast` et `unicast` ;
FR * remplace le protocole `RRP` (_Redundant Ring Protocole_).
FR
Corosync 3 uses the `kronosnet` (`knet`) library, which:

* replaces the `multicast` and `unicast` method,
* replaces the `RRP` protocol (_Redundant Ring Protocol_)

FR Corosync implémente le protocole _Totem Single Ring Ordering and Membership_ pour la gestion
FR des messages et des groupes. Il est possible de redonder les canaux de communications ou liens
FR en créant plusieurs interfaces (option `totem` > `interface` > `linknumber`) qui seront
FR utilisés comme support des rings (option `nodelist` > `node` > `ringX_addr`). `knet` permet
FR de créer jusqu'à 8 liens avec des protocoles et des priorités différentes.
FR
FR Le chiffrement peut être configuré soit avec l'option `totem` > `secauth` soit avec les
FR paramètres `totem` > `crypto_model`, `totem` > `crypto_cipher` et `totem` > `crypto_hash`.
FR
FR Il est également possible d'utiliser la compression.
FR
Corosync implements the _Totem Single Ring Ordering and Membership_ protocol
for its message and group management. It's possible to add redundancy for
communication channels and network links by creating several interfaces
(`totem` > `interface` > `linknumer` option) which will be used by the rings
(`nodelist` > `node` > `ringX_addr`). `knet` allows for the creation of
up to 8 links with different protocols and priorities.

Cryptography can be configured either with the option `totem` > `secauth` or
the parameters `totem` > `crypto_model`, `totem` > `crypto_cipher` and `totem`
> `crypto_hash`.

It's also possible to use compression.

:::

-----

## Two node clusters

FR * paramètre dédié : `two_node: 1`
FR * option héritée de CMAN
FR * requiers `expected-votes: 2`
FR * implique `wait_for_all: 1`
FR * requiers un fencing hardware configuré sur la même interface que le heartbeat
FR
* dedicated parameter: `two_node: 1`
* inherited from CMAN
* requires: `expected-votes: 2`
* implies: `wait_for_all: 1`
* requiers a fencing hardware configured on the same interface as the
  heartbeat.

::: notes

FR Considérons un cluster à deux nœuds avec un vote par nœud. Le nombre de vote
FR attendu est 2 (`expected-votes`), il n'est donc pas possible d'avoir une
FR majorité en cas de partition du cluster. La configuration `two_node` permet de
FR fixer artificiellement le quorum à 1 et de résoudre ce problème.
FR
Given a two cluster node with one vote per node, the number of expected vote is
2 (`expected-votes`). Therefore, it's not possible to have a majority in case
of cluster partition. The `two_node` parameter fixes this problem by fixing the
quorum at a value of 1.

CR Ce paramétrage, implique `wait_for_all : 1` qui empêche le cluster d'établir
CR une majorité tant que l'ensemble des nœuds n'est pas présent. Ce qui évite une
CR partition au démarrage du cluster.
CR 
This configuration implies the usage of `wait_for_all: 1`, which forbids the
cluster from establishing a majority unless all members of the cluster are
present. This restriction is designed to avoid a partition during cluster
startup.

CR En cas de partition réseau, les deux nœuds font la course pour fencer l'autre.
CR Le nœud vainqueur conserve alors le quorum grâce au paramètre `two_node: 1`.
CR Quand au second nœud, après redémarrage de Pacemaker, si la partition réseau
CR existe toujours, ce dernier n'obtient donc pas le quorum grâce au paramètre
CR `wait_for_all: 1` et en conséquence ne peut démarrer aucune ressource.
CR
In case of network partition, both nodes race to fence the other node. The
winner keeps the quorum thanks to the parameter `two_node: 1`. If the second
node is restarted while the partition is still present, it will not be able to
archive the quorum thanks to the parameter `wait_for_all: 1`. As a result it
will bot be able to start any ressource.

FR Même si elle fonctionne, ce genre de configuration n'est cependant pas
FR optimale. Comme en témoigne
FR [cet article du blog de clusterlabs](http://blog.clusterlabs.org/blog/2018/two-node-problems).
FR
Even though this kind of configuration works, it's not optimal as explained in
[this clusterlab blog
post](http://blog.clusterlabs.org/blog/2018/two-node-problems).

:::

-----

## Tools

FR Corosync installe plusieurs outils:
FR
FR * `corosync-cfgtool` : administration, paramétrage
FR * `corosync-cpgtool` : visualisation des différents groupes CPG
FR * `corosync-cmapctl` : administration de la base d'objets
FR * `corosync-quorumtool` : gestion du quorum
FR
Corosync installs several tools:

* `corosync-cfgtool` : administration, configuration
* `corosync-cpgtool` : cpg group visualization
* `corosync-cmapctl` : administration of the cmap key value store
* `corosync-quorumtool` : quorum managment
<!-- pas sur d'avoir bien compris la ligne cmap -->

::: notes

FR `corosync-cfgtool` permet de :
FR
FR * arrêter corosync sur le serveur ;
FR * récupérer l'IP d'un nœud ;
FR * tuer un nœud ;
FR * récupérer des informations sur les rings et réinitialiser leur statut ;
FR * demander à l'ensemble des nœuds de recharger leur configuration.
FR
`corosync-cfgtool` can be used to:

* stop corosync on the server;
* retrieve the IP of a node;
* kill a node;
* retrieve information about rings and reinitialize their status;
* ask all nodes to reload their configuration.

FR `corosync-cpgtool` permet d'afficher les groupes cpg et leurs membres.
FR
`corosync-cpgtool` can be used to display cpg groups and members.

FR `corosync-cmapctl` permet de manipuler et consulter la base d'objet de corosync,
FR les actions possibles sont :
FR
FR * lister les valeurs associées aux clés : directement (ex: totem.secauth), par
FR préfix(ex: totem.) ou sans filtre ;
FR * définir ou supprimer des valeurs ;
FR * changer la configuration depuis un fichier externe ;
FR * suivre les modifications des clés stockées dans `cmap` en temps réel en filtrant
FR sur un préfix ou directement sur un clé.
FR
`corosync-cmapctl` can be used to read and modify data in the key value store
of corosync, possible actions are:

* list the values for given keys: directrly (e.g.: totem.secauth), using a
  prefix (e.g.: totem.) or without filters;
* define or delete values;
* change the configuration using an external file;
* follow the modification of keys sorted in `cmap` in realtime.

FR `corosync-quorumtool` permet d'accéder au service de quorum pour par exemple:
FR
FR * modifier la configuration des votes (nombre, nombre attendu) ;
FR * suivre les modifications de quorum ;
FR * lister les nœuds avec leurs nom, id et IPs .
FR
`corosync-quorumtool` can be used to access the quorum service in order to:

* modify the configuration of votes (number & avaited number);
* follow quorum evolution;
* list nodes with their name, id and ips.

:::

-----

## Practice work: Corosync utilisation

::: notes

FR 1. afficher le statut du ring local avec `corosync-cfgtool`
FR 2. afficher l'IP de chaque nœud avec `corosync-cfgtool`
FR 3. afficher les groupes CPG et leurs membres avec `corosync-cpgtool`
FR 4. afficher la configuration des nœuds dans la base CMAP avec
FR    `corosync-cmapctl` (clé `nodelist`)
FR 5. afficher l'état du quorum avec `corosync-quorumtool`
FR
1. display the local ring status with `corosync-cfgtool`
2. display the IP of each node with `corosync-cfgtool`
3. display CPG groups and members with `corosync-cpgtool`
4. display the configuration of each node from the CMAP base with
   `corosync-cmapctl` (key: `nodelist`)
5. display the state of the quorum with `corosync-quorumtool`

:::

-----

## Correction: Corosync utilisation

::: notes

FR 1. afficher le statut du ring local avec `corosync-cfgtool`
FR
1. display the local ring status with `corosync-cfgtool`

~~~console
# corosync-cfgtool -s
Printing ring status.
Local node ID 1
RING ID 0
  id  = 10.20.30.6
  status  = ring 0 active with no faults
~~~

FR 2. afficher l'IP de chaque nœud avec `corosync-cfgtool`
FR
2. display the IP of each node with `corosync-cfgtool`

~~~console
# corosync-cfgtool -a 1
10.20.30.6

# corosync-cfgtool -a 2
10.20.30.7

# corosync-cfgtool -a 3
10.20.30.8
~~~

FR 3. afficher les groupes CPG et leurs membres avec `corosync-cpgtool`
FR
3. display CPG groups and members with `corosync-cpgtool`

~~~console
# corosync-cpgtool -e
Group Name	       PID	   Node ID
crmd
		      6912	         1 (10.20.30.6)
		      6647	         3 (10.20.30.8)
		      6727	         2 (10.20.30.7)
attrd
		      6910	         1 (10.20.30.6)
		      6645	         3 (10.20.30.8)
		      6725	         2 (10.20.30.7)
stonith-ng
		      6908	         1 (10.20.30.6)
		      6643	         3 (10.20.30.8)
		      6723	         2 (10.20.30.7)
cib
		      6907	         1 (10.20.30.6)
		      6642	         3 (10.20.30.8)
		      6722	         2 (10.20.30.7)
pacemakerd
		      6906	         1 (10.20.30.6)
		      6641	         3 (10.20.30.8)
		      6721	         2 (10.20.30.7)
~~~

FR Chaque sous-processus de pacemaker est associé à un groupe de communication
FR avec leur équivalents sur les autres nœuds du cluster.
FR
Each sub process of pacemaker is part of a communication group with it's
counterpart on the other nodes.

FR 4. afficher la configuration des nœuds dans la base CMAP avec
FR    `corosync-cmapctl` (clé `nodelist`)
FR
4. display the configuration of each node from the CMAP base with
   `corosync-cmapctl` (key: `nodelist`)

~~~console
# corosync-cmapctl -b nodelist
nodelist.local_node_pos (u32) = 0
nodelist.node.0.nodeid (u32) = 1
nodelist.node.0.ring0_addr (str) = hanode1
nodelist.node.1.nodeid (u32) = 2
nodelist.node.1.ring0_addr (str) = hanode2
nodelist.node.2.nodeid (u32) = 3
nodelist.node.2.ring0_addr (str) = hanode3
~~~

FR 5. afficher l'état du quorum avec `corosync-quorumtool`
FR
5. display the state of the quorum with `corosync-quorumtool`

~~~console
# corosync-quorumtool
Quorum information
------------------
Date:             ...
Quorum provider:  corosync_votequorum
Nodes:            3
Node ID:          1
Ring ID:          3/8
Quorate:          Yes

Votequorum information
----------------------
Expected votes:   3
Highest expected: 3
Total votes:      3
Quorum:           2  
Flags:            Quorate 

Membership information
----------------------
    Nodeid      Votes Name
         3          1 hanode3
         2          1 hanode2
         1          1 hanode1 (local)
~~~

:::

-----


# Components of the cluster

![Diagramme complet](medias/pcmk-archi-all.png)

::: notes

FR Dans ce chapitre, nous abordons rapidement l'architecture de Pacemaker en détaillant ses
FR sous processus. Le but est de comprendre le rôle de chaque brique et ainsi mieux
FR diagnostiquer l'état du cluster, son paramétrage et savoir interpréter les messages de
FR log correctement. Voici les différents processus tel que démarrés par Pacemaker:
FR
In this chapter, we will do an overview of Pacemaker's architecture and focus
on it's sub processes. The objective is to understand the role of each part in
order to have an easier time diagnosing the cluster state, understanding it's
configuration and interpreting the log messages correctly.

~~~
/usr/sbin/pacemakerd -f
\_ /usr/libexec/pacemaker/cib
\_ /usr/libexec/pacemaker/stonithd
\_ /usr/libexec/pacemaker/lrmd
\_ /usr/libexec/pacemaker/attrd
\_ /usr/libexec/pacemaker/pengine
\_ /usr/libexec/pacemaker/crmd
~~~

FR Le diagramme présente les différents éléments de Pacemaker au sein d'un cluster à trois
FR nœuds. Une vue plus détaillée mais centrée sur un seul nœud est présenté dans la
FR documentation de Pacemaker. Voir:
FR
FR [Schémas de l'architecture interne de Pacemaker](http://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/_pacemaker_architecture.html#_internal_components)
FR
This diagram shows the different components of Pacemaker in a three node
cluster. A more detailed view, focused on a single node is present in
Pacemaker's documentation. See:

[Schemas of the internal architecture of Pacemaker](http://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/_pacemaker_architecture.html#_internal_components)

FR Cette architecture et le paramétrage de Pacemaker permet de supporter différents types de
FR scénario de cluster dont certains (vieux) exemples sont présentés dans le wiki de
FR Pacemaker:
FR
FR [Schémas des différentes configuration de nœuds possibles avec Pacemaker](https://wiki.clusterlabs.org/wiki/Pacemaker#Example_Configurations)
FR
This architecture is designed to support different types of clusters. Some
(old) example are present in the Pacemaker wiki:

[Schemas of different cluster configuration in pacemaker](https://wiki.clusterlabs.org/wiki/Pacemaker#Example_Configurations)

:::


-----

## Cluster Information Base (CIB)

FR * détient la configuration du cluster
FR * l'état des différentes ressources
FR * un historique des actions exécutées
FR * stockage fichier au format XML
FR * synchronisé automatiquement entre les nœuds
FR * historisé
FR * géré par le processus `cib`
FR * renommé `pacemaker-based` depuis la version 2.0
FR
* contains:
  - the cluster configuration
  - the state of the resources
  - an history of the latest actions
* stored in XML format
* automatically synchronized between nodes
* archived
* managed by the `cib` process
  - renamed `pacemaker-based` since version 2.0

::: notes

FR La CIB est la représentation interne de la configuration et de l'état des composantes du
FR cluster. C'est un fichier XML, créée par Pacemaker à l'initialisation du cluster et qui
FR évolue ensuite au fil des configurations et évènements du cluster.
FR
The CIB is a internal representation of the configuration and state of the
cluster's components and resources. It's an XML file, created by Pacemaker
during cluster initialization. It evolves as the cluster configuration changes
and events takes place in the cluster.

FR En fonction de cet ensemble d'états et du paramétrage fourni, le cluster détermine l'état
FR idéal de chaque ressource qu'il gère (démarré/arrêté/promu et sur quel serveur) et
FR calcule les transitions permettant d'atteindre cet état.
FR
From the component states and configuration, the cluster determines the ideal
state for each managed resource (started/stopped/promoted and on which server)
and computes the transitions necessary to reach this state.

FR Le processus `cib` est chargé d'appliquer les modifications dans la CIB, de
FR conserver les information transitoires en mémoire (statuts, certains scores, etc) et de
FR notifier les autres processus de ces modifications si nécessaire.
FR
The `cib` process (`pacemaker-based`) is tasked to apply the modification
inside the CIB, keep track of transient information (status, some scores, etc.)
ad notify the other processes of the changes if it's necessary.

FR Le contenu de la CIB est historisé puis systématiquement synchronisé entre les nœuds à
FR chaque modification. Ces fichiers sont stockés dans `/var/lib/pacemaker/cib` :
FR
The content of the CIB is archived and synchronized between all nodes after
each modification. These files are stored in `/var/lib/pacemaker/cib`.

~~~
ls /var/lib/pacemaker/cib/ -alh
total 68K
drwxr-x--- 2 hacluster haclient 4.0K Feb  7 16:46 .
drwxr-x--- 6 hacluster haclient 4.0K Feb  7 12:16 ..
-rw------- 1 hacluster haclient  258 Feb  7 16:43 cib-1.raw
-rw------- 1 hacluster haclient   32 Feb  7 16:43 cib-1.raw.sig
-rw------- 1 hacluster haclient  442 Feb  7 16:43 cib-2.raw
-rw------- 1 hacluster haclient   32 Feb  7 16:43 cib-2.raw.sig
-rw------- 1 hacluster haclient  639 Feb  7 16:43 cib-3.raw
-rw------- 1 hacluster haclient   32 Feb  7 16:43 cib-3.raw.sig
-rw------- 1 hacluster haclient  959 Feb  7 16:43 cib-4.raw
-rw------- 1 hacluster haclient   32 Feb  7 16:43 cib-4.raw.sig
-rw------- 1 hacluster haclient  959 Feb  7 16:43 cib-5.raw
-rw------- 1 hacluster haclient   32 Feb  7 16:43 cib-5.raw.sig
-rw------- 1 hacluster haclient  959 Feb  7 16:46 cib-6.raw
-rw------- 1 hacluster haclient   32 Feb  7 16:46 cib-6.raw.sig
-rw-r----- 1 hacluster haclient    1 Feb  7 16:46 cib.last
-rw------- 1 hacluster haclient  959 Feb  7 16:46 cib.xml
-rw------- 1 hacluster haclient   32 Feb  7 16:46 cib.xml.sig
~~~

FR `cib.xml` correspond à la version courante de la CIB, les autres fichiers `cib-*.raw`,
FR aux versions précédentes.
FR
`cib.xml` is the current version of the CIB, the `cib-*.raw` files are older
versions of it.

FR Par défaut, Pacemaker conserve toutes les versions de la CIB depuis la création du
FR cluster. Il est recommandé de limiter ce nombre de fichier grâce aux paramètres
FR `pe-error-series-max`, `pe-warn-series-max` et `pe-input-series-max`.
FR
By default, Pacemaker keep all the versions of the CIB since cluster creation.
It's advised to limit the amount of files kept with the parameters:
`pe-error-series-max`, `pe-warn-series-max` and `pe-input-series-max`.

FR Il n'est pas recommandé d'éditer la CIB directement en XML. Préférez toujours utiliser
FR les commandes de haut niveau proposées par `pcs` ou `crm`. En dernier recours, utilisez
FR l'outil `cibadmin`.
FR
Making modification by editing the CIB directly is not recommanded. A better
practice is to used the high level commands available in `pcs` or `crm`. As a
last resort, the `cibadmin` tool is available.

:::

-----

### Practice work: CIB

::: notes

FR 1. consulter le contenu de ce répertoire où est stockée la CIB
FR 2. identifier la dernière version de la CIB
FR 3. comparer avec `cibadmin --query` et `pcs cluster cib`
FR
1. check the content of the directory where the CIB is stored
2. identify the last version of the CIB
3. compare the output of the commands `cibadmin --query` and `pcs cluster cib`

:::

-----

### Correction: CIB

::: notes

FR 1. consulter le contenu de ce répertoire où est stockée la CIB
FR
1. check the content of the directory where the CIB is stored

~~~
# ls /var/lib/pacemaker/cib
~~~

FR 2. identifier la dernière version de la CIB
FR
FR La version courante de la CIB est stockée dans
FR `/var/lib/pacemaker/cib/cib.xml`. Sa version est stockée dans
FR `/var/lib/pacemaker/cib/cib.last`.
FR
2. identify the last version of the CIB

The current version of the CIB is stored in `/var/lib/pacemaker/cib/cib.xml`.
It's version is stored in `/var/lib/pacemaker/cib/cib.last`.

FR 3. comparer avec `cibadmin --query` et `pcs cluster cib`
FR
FR Vous observez une section `<status\>` supplémentaire dans le document
FR XML présenté par `cibadmin`. Cette section contient l'état du cluster et est
FR uniquement conservée en mémoire.
FR

3. compare the output of the commands `cibadmin --query` and `pcs cluster cib`

There is a additional `<status\>` section in the XML document presented by
`cibadmin`.  This section contains the cluster state and is only kept in
memory which explains why it's onlu visible with `cibadmin`.

:::

-----

### Designated Controler (DC) - Global diagram

![DC diagram](medias/pcmk-archi-dc.png)

-----

## Designated Controler (DC)

FR * daemon `CRMd` désigné pilote principal sur un nœud uniquement
FR * lit et écrit dans la CIB
FR * invoque PEngine pour générer les éventuelles transitions
FR * contrôle le déroulement des transitions
FR * envoie les actions à réaliser aux daemons `CRMd` des autres nœuds
FR * possède les journaux applicatifs les plus complets
FR

* a `CRMd` daemon appointed as the manager of the cluster
  - present only on one node
* read and write from/to the CIB
* calls the PEngine to generate the necessary transitions
* control the proceeding of transitions
* sends the actions to the daemons`CRMd` of other nodes
* has the most complete traces of all nodes

::: notes

FR Le *Designated Controler* est élu au sein du cluster une fois le groupe de communication
FR établi au niveau de Corosync. Il pilote l'ensemble du cluster.
FR
FR Il est responsable de:
FR
FR * lire l'état courant dans la CIB
FR * invoquer le `PEngine` en cas d'écart avec l'état
FR   stable (changement d'état d'un service, changement de configuration, évolution des
FR   scores ou des attributs, etc)
FR * mettre à jour la CIB (mises à jour propagée aux autres nœuds)
FR * transmettre aux `CRMd` distants une à une les actions à réaliser sur leur nœud
FR
FR C'est le DC qui maintient l'état primaire de la CIB ("master copy").
FR
<!-- saut a la ligne absent pour "invoquer le Pengine" dans la version en ligne -->

The *Designated Controler* is elected once a communication group is established
by Corosync. It manages the whole cluster.

It's responsible for:

* reading the current state in the CIB
* invoking the `PEngine` if the state of the cluster is different from it's
  expected state (service state change, configuration change, evolution of
  scores or attributes, etc.)
* updates the CIB (the updates sent to all nodes)
* dictate the actions that have to be executed to the relevant remote `CRMd`
  processes, theses changes are send one at a time

The DC is responsible for the _master copy_ of the CIB.
<!-- Est ce que master copy suffit a un anglais pour comprendre de quoi on parle la ? -->

:::

-----

### PEngine - Global Diagram

![PEngine diagram](medias/pcmk-archi-pengine.png)

-----

## Policy Engine (PEngine)

FR * reçoit en entrée les informations d'état des ressources et le paramétrage
FR * décide de l'état idéal du cluster
FR * génère un graphe de transition pour atteindre cet état
FR * renommé `Scheduler` depuis la version 2.0
FR * peut être consulté grâce à la commande `crm_simulate`
FR
FR ![Diagramme Scheduler - calcul graphe de transition](medias/pcmk-archi-transition.png)

* receives information about the state of resources and configuration
* decides the ideal state for the cluster
* creates a transition graph to reach the ideal state
* renamed `Scheduler` in version 2.0
* can be leveraged with the `crm_simulate` command

![Diagramme Scheduler - transition graph calculation](medias/pcmk-archi-transition.png)

::: notes

FR Le `PEngine` est la brique de Pacemaker qui calcule les transitions nécessaires pour
FR passer d'un état à l'autre.
FR
FR Il reçoit en entrée des informations d'état et de paramétrage au format XML (extrait de
FR la CIB), détermine si un nouvel état est disponible pour les ressources du cluster, et
FR calcule toutes les actions à mettre en œuvre pour l'atteindre.
FR
FR Toutes ces actions sont regroupées au sein d'un graph de transition que le
FR `Designated Controller`, qui pilote le cluster, devra ensuite mettre en œuvre.
FR
The `PEngine` is the Pacemaker component responsible for the computation of the
transition necessary to go from one state to another.

It receives information about states and configuration in XML format (from the
CIB), decides if a new state is available and computes all the actions
necessary to reach it.

All theses actions are gathered in a transition graph which will be applied by
the component responsible for decision making: the `Designated Controller`.

FR Voici un exemple de transition complexe présentant une bascule maître-esclave DRBD:
FR ![Diagramme exemple de transition complexe](medias/Policy-Engine-big.png)
FR
FR Ce diagramme vient de la documentation de Pacemaker. L'original est disponible à cette
FR adresse:
FR <https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Administration/images/Policy-Engine-big.png>
FR
FR Les explications sur les codes couleurs sont disponibles à cette adresse:
FR <https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Administration/_visualizing_the_action_sequence.html>
FR
This is an example of complex transition graph involving a master slave DRBD
switchover.
![example diagram for a complex transition](medias/Policy-Engine-big.png)

This diagram comes from the Pacemaker documentation. The original is available
at:
<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Administration/images/Policy-Engine-big.png>

The explanation of the color code is available at this address:
<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Administration/_visualizing_the_action_sequence.html>

FR Dans cet exemple chaque flèche impose une dépendance et un ordre entre les actions. Pour
FR qu'une action soit déclenchée, toutes les actions précédentes doivent être exécutées et
FR réussies. Les textes en jaune sont des "actions virtuelles", simples points de passage
FR permettant de synchroniser les actions entre elles avant de poursuivre les suivantes. Les
FR textes en noir représentent des actions à exécuter sur l'un des nœuds du cluster.
FR
FR Le format des textes est le suivant: `<resource>_<action>_<interval>`
FR
FR Une action avec un intervalle à 0 est une action ponctuelle (`start`, `stop`, etc). Une
FR action avec un intervalle supérieur à 0 est une action récurrente, tel que `monitor`.
FR
In this example each arrow represents a dependancy and forces an order of
execution between actions. In an order for an action to be triggered, all the
preceding actions must have been executed and have succeded. The yellow texts
represent virtual actions, they act as synchronisation points when several
actions are required before starting another one. The black texts represent
actions that must be executed on a cluster node.

The format of the text is the following: `<resource>_<action>_<interval>`.

An action with an interval of zero is a one off action (`start`, `stop`, etc.).
Actions with intervals superior to zero are recurring action such as `monitor`.

FR Dans cet exemple:
FR
FR * les actions 1 à 4 concernent l'exécution des actions `notify pre-demote` sur les nœuds
FR   "frigg" et "odin" du cluster
FR * l'action 1 déclenche en parallèle les deux actions 2 et 3
FR * l'action 4 est réalisée une fois que les actions 1, 2 et 3 sont validées
FR * l'action 5 est exécutée n'importe quand
FR * l'action 5 interrompt l'exécution récurrente de l'action `monitor` sur la ressource
FR   "drbd0:0" du serveur "frigg"
FR * l'action 7 est exécutée après que 5 et 6 soient validées
FR * l'action 7 effectue un `demote` de la ressource "drbd0:0" sur "frigg" (qui n'est donc
FR   plus supervisée)
FR * la pseudo action 8 est réalisée une fois que l'action `demote` est terminée
FR * la pseudo action 9 initialise le déclenchement des actions `notify post-demote` et
FR   dépend de la réalisation précédente de la notification "pre-demote" et de l'action
FR   `demote` elle même
FR * les actions 9 à 12 représentent l'exécution des notifications `post-demote` dans tout
FR   le cluster
FR * les actions 13 à 24 représentent les actions de `notify pre-promote`, `promote` de
FR   drbd sur "odin" et `notify post-promote` au sein du cluster
FR * les actions 25 et 27 peuvent alors être exécutées et redémarrent les actions de
FR   monitoring récurrentes de drbd sur "odin" et "frigg"
FR * les actions 26, 28 à 30 démarrent un groupe de ressource dépendant de la ressource
FR   drbd
FR
In this example:

* action 1 to 4 are `notify pre-demote` actions executed on the nodes "frigg"
  and "odin"
  - action 1 is used to start action 2 and 3 in parallel
  - action 4 is done after action 1, 2 and 3 are completed sucessfully
* action 5 is executed at any time
* action 5 cancels the recurring execution of the `monitor` action on ressource
  "drbd0:0" of server "frigg"
* action 7 is executed after action 5 and 6 are deemed valid
* action 7 `demotes` the ressource "drbd0:0" on server "frigg" (it is therefore
  no longer monitored)
* action 8 is a pseudo action triggered once the `demote` is finished
* action 9 is a pseudo action responsible for starting the the two `notify
  post-demote` actions. It requires the `pre-demote` notification and the
  `demote` action
* action 9 to 12 represent the execution of the `post-demote` actions in the
  whole cluster
* action 13 to 24 represent the execution of the `notify-pre-demote` and
  `demote` action on the drbd resource of "odin". `notify post-demote` is a
  cluster wide action
* action 25 to 27 can then be executed and restart the recurring monitoring
  actions of drbd on "odin" and "frigg"
* action 26, 28 and 29 start the group of resource which depends on the drbd
  resource
<!-- relire -->

FR Enfin, il est possible de consulter les transitions proposées par le PEngine
FR grâce à la commande `crm_simulate`. Cette commande est aussi parfois utile
FR pour en extraire des informations disponibles nulles par ailleurs, comme les
FR [scores de localisation][Contraintes de localisation].
FR
Finally, it's possible to check the transitions proposed by PEngine with the
command `crm_simulate`. This command is also sometimes useful to get
information that are not accessible elsewhere like the [location
scores][Localisation constraints].

:::

-----

### Practical work: PEngine

::: notes

FR 1. identifier sur quels nœuds est lancé le processus `pengine`
FR 2. identifier où se trouvent les logs de `pengine`
FR 3. identifier le DC
FR 4. observer la différence de contenu des log de `pengine` entre nœuds
FR 5. afficher la vision de PEngine sur l'état du cluster (`crm_simulate`)
FR
1. identify on which node the processus `pengine` is started.
2. identify where are the logs of the `pengine`
3. identify the DC
4. check the difference between the content of the `pengine` logs across nodes
5. display the PEngine point of view of the cluster state (`¢rm_simulate`)

:::

-----

### Correction: PEngine

::: notes

FR 1. identifier sur quels nœuds est lancé le processus `pengine`
FR
FR Sur tous les nœuds.
FR
1. identify on which node the processus `pengine` is started.

On all nodes

FR 2. identifier où se trouvent les logs de `pengine`
FR
FR Les messages de `pengine` se situent dans `/var/log/cluster/corosync.log`,
FR mélangés avec ceux des autres sous processus.
FR
FR Il est aussi possible de les retrouver dans `/var/log/messages` ou ailleurs en
FR fonction de la configuration de corosync, syslog, etc.
FR
2. identify where are the logs of the `pengine`

The `pengine` logs is located in `/var/log/cluster/corosync.log`, it's mixed
with the other processus logs.

It's also possible to find these messages in `/var/log/messages` or wherever
the configuration of corosync, syslog, etc. dictates it.

FR 3. identifier le DC
FR
FR Utiliser `crm_mon`, `pcs status` ou `crmadmin`:
FR
3. identify the DC

Use `crm_mon`, `pcs status` or `crmadmin`:

~~~console
# crmadmin -D
Designated Controller is: hanode3
~~~

FR 4. observer la différence de contenu des log de `pengine` entre nœuds
FR
FR Seuls le DC possède les messages relatifs au calcul de transitions effectués
FR par le sous-processus `pengine`.
FR
4. check the difference between the content of the `pengine` logs across nodes

The message related to the transition calculation done by the `pengine` sub
process are only available on the DC.

FR 5. afficher la vision de PEngine sur l'état du cluster (`crm_simulate`)
FR
5. display the PEngine point of view of the cluster state (`¢rm_simulate`)

~~~console
# crm_simulate --live-check

Current cluster status:
Online: [ hanode1 hanode2 hanode3 ]

~~~

:::

-----

### Cluster Resource Manager (CRM) - Global diagram

![CRM Diagram](medias/pcmk-archi-crmd.png)

-----

## Cluster Resource Manager (CRM)

FR * daemon `CRMd` local à chaque nœud
FR * chargé du pilotage des événements
FR * reçoit des instructions du `PEngine` s'il est DC ou du `CRMd` DC distant
FR * transmet les actions à réaliser au sein des transitions
FR   * au daemon `LRMd` local
FR   * au daemon `STONITHd` local
FR * récupère les codes retours des actions
FR * transmets les codes retours de chaque action au `CRMd` DC
FR * renommé `controller` depuis la version 2.0
FR
* local daemon `CRMd` on each node
* tasked with event management
* receives instructions from `PEngine` if it's the DC or from a remote `CRMd`
  otherwise (the DC)
* transmits the actions
  * to the local `LRMd` daemon
  * to the local `STONITHd` daemon
* fetches the return code of the actions
* resends these return code to `CRMDd` on the DC
* renamed `controller` in version 2.0

::: notes

<!-- local qui pilote (ligne 1) -->
FR Le  daemon `CRMd` est local à chaque nœud qui pilote les événements. Il peut soit être
FR actif (DC), et donc être chargé de l'ensemble du pilotage du cluster, soit passif, et
FR attendre que le `CRMd` DC lui fournisse des instructions.
FR
FR Lorsque des instructions lui sont transmises, il les communique aux daemons `LRMd` et/ou
FR `STONITHd` locaux pour qu'ils exécutent les actions appropriées auprès des _ressources
FR agents_ et _fencing agents_.
FR
FR Une fois l'action réalisée, le `CRMd` récupère le statut de l'action (via
FR son code retour) et le transmet au `CRMd` DC qui en valide la cohérence
FR avec ce qui est attendu au sein de la transition.
FR
FR En cas de code retour différent de celui attendu, le `CRMd` DC décide d'annuler la
FR transition en cours. Il demande alors une nouvelle transition au `PEngine`.
FR
The `CRMd` daemon is local to each nodes and manages events. It can be active
(DC) in which case it's in charge of managing the whole cluster, or passive in
which case it recieves instructions from the `CRMd` DC.

When instructions are fed to `CRMd`, it communicates with the local `LRMd`
and/or local `STONITHd` so that the appropriate actions can be executed by
the _resource agents_ and _fencing agents_.

Once the action is finished, `CRMd` fetches the status of the action (via the
return code) and  transmits it to the `CRMd` DC. The DC validates the coherence
of the result with what was expected in the transition.

If the return code is different from the expected one, the `CRMd` DC decides to
cancel the current transaction and asks for a new transition from the
`PEngine`.

:::

-----

### Practical work: Cluster Resource Manager

::: notes

FR 1. trouver comment sont désignés les messages du `CRMd` dans les log
FR 2. identifier dans les log qui est le DC
FR
1. find how the `CRMd` messages are tagged in the logs
2. identify which server is the DC in the logs

:::

-----

### Correction: Cluster Resource Manager

Study of the `CRMd` daemon.

::: notes

FR 1. trouver comment sont désignés les messages du `CRMd` dans les log
FR
FR Les messages de ce sous-processus sont identifiés par `crmd:`.
FR
1. find how the `CRMd` messages are tagged in the logs

The messages from this sub process are identified with `crmd:`

FR 2. identifier dans les log qui est le DC
FR
2. identify which server is the DC in the logs
~~~
crmd:     info: update_dc:    Set DC to hanode1 (3.0.14)
~~~

FR À noter que le retrait d'un DC est aussi visible:
FR
When a DC is demoted, it's also visible:

~~~
crmd:     info: update_dc:    Unset DC. Was hanode2
~~~

:::

-----

## `STONITHd` and _Fencing Agent_

![Fencing diagram](medias/pcmk-archi-fencing.png)

-----

### `STONITHd`

<!-- renomé fencer ou pacemaker-fenced c'est pas trop clair j'ai pris fencer-->
FR * daemon `STONITHd`
FR * gestionnaire des agents de fencing (_FA_)
FR * utilise l'API des fencing agent pour exécuter les actions demandées
FR * reçoit des commandes du `CRMd` et les passe aux _FA_
FR * renvoie le code de retour de l'action au `CRMd`
FR * support de plusieurs niveau de fencing avec ordre de priorité
FR * outil `stonith-admin`
FR * renommé `fenced` depuis la version 2.0
FR
* `STONITHd` daemon
* fencing agent manager (_FA_)
* uses the fencing agent API to execute the requiered actions
* recieves the commands from `CRMd` and feeds them to the _FA_
* resends the return code of the actions to `CRMd`
* supports several level of fencing with a priority order
* `stonith-admin` tool
* renamed `fencer` since version 2.0

::: notes

<!-- ça fait bizarre de dire ça car on n'a pas encore parlé de LRMd -->
<!-- pour -l et -Q ça ne semble pas être ça (cf anglais) -->
FR Le daemon `STONITHd` joue sensiblement un rôle identique à celui du `LRMd` vis-à-vis des
FR agents de fencing (_FA_).

FR
FR L'outil `stonith-admin` permet d'interagir avec le daemon `STONITHd`, notamment:
FR
FR * `stonith_admin -V --list-registered` : liste les agents configurés
FR * `stonith_admin -V --list-installed` : liste tous les agents disponibles
FR * `stonith_admin -V -l <nœud>` : liste les agents contrôlant le nœud spécifié.
FR * `stonith_admin -V -Q <nœud>` : contrôle l'état d'un nœud.
FR
The `STONITHd` daemon is for the fencing agents (_FA_) what `LRMd` is for
resource agents (_RA_).

The `stonith-admin` tool can be used to interact with the `STONITHd` daemon,
for example:

* `stonith_admin -V --list-registered` : list the configured agents
* `stonith_admin -V --list-installed` : list the available agents
* `stonith_admin -V -l <nœud>` : list the agents that can terminate the
  specified node
* `stonith_admin -V -Q <nœud>` : controls the state of a device on a node

:::

-----

### _Fencing Agent_ (_FA_)

FR * script permettant de traduire les instructions du _fencer_ vers l'outil de fencing
FR * doit assurer que le nœud cible est bien complètement isolé du cluster
FR * doit renvoyer des codes retours définis dans l'API des _FA_ en fonction des résultats
FR * dix actions disponibles dans l'API, toutes ne sont pas obligatoires
FR
* script designed to translate `fencer`'s instruction to the fencing device
* must guaranty that the target node is isolated from the reste of the cluster
* must return the approriate return codes as defined in the fencing agent API
* ten actions are availagble in the API, the are not all mandatory

::: notes

FR Attention aux _FA_ qui dépendent du nœud cible !
FR
FR Exemple classique : la carte IPMI. Si le serveur a une coupure électrique le
FR _FA_ (la carte IPMI donc) n'est plus joignable. Pacemaker ne reçoit donc
FR aucune réponse et ne peut pas savoir si le fencing a fonctionné, ce qui
FR empêche toute bascule.
FR
FR Il est conseillé de chaîner plusieurs _FA_ si la méthode de fencing présente
FR un _SPoF_: IPMI, rack d'alimentation, switch réseau ou SAN, ...
FR
Be wary of _FA_ that depend on the node state !

<!-- the FA or the fencing device is no longer reachable ? are both terms in
terchangeable here ? -->
Example: the IPMI card. If the server as an electrical outage, the _FA_ (the
IPMI card) is no longer reachable. Pacemaker can't receive feedback from it
therefore it cannot know if the fencing was successful, which can prevent a
failover.

In such cases, where the fencing is a _SPoF_ (IMPI, rack power supply, network
switch or SAN ..), it's a good practice to chaine several _FA_.

<!-- reformuler la différence entre status et monitor ? -->
FR Voici les actions disponibles de l'API des FA:
FR
FR * `off`: implémentation obligatoire. Permet d'isoler la ressource ou le serveur
FR * `on`: libère la ressource ou démarre le serveur
FR * `reboot`: isoler et libérer la ressource. Si non implémentée, le daemon
FR   exécute les actions off et on.
FR * `status`: permet de vérifier la disponibilité de l'agent de fencing et le
FR   statut du dispositif concerné: on ou off
FR * `monitor`: permet de vérifier la disponibilité de l'agent de fencing
FR * `list`: permet de vérifier la disponibilité de l'agent de fencing et de
FR   lister l'ensemble des dispositifs que l'agent est capable d'isoler (cas d'un
FR   hyperviseur, d'un PDU, etc)
FR * `list-status`: comme l'action `list`, mais ajoute le statut de chaque dispositif
FR * `validate-all`: valide la configuration de la ressource
FR * `meta-data`: présente les capacités de l'agent au cluster
FR * `manpage`: nom de la page de manuelle de l'agent de fencing
FR

The following action are available in the _FA_ API:

* `off`: mandatory action, enables the isolation of a resource of server
* `on`: frees a resource or start a server
* `reboot`: isolate and restart a resource. If the action is not available the
  daemon will execute the off and on actions
* `status`: check to see if a local stonith device's port is reachable
* `monitor`: check to see if a local stonith device is reachable
* `list`: listing hosts and port assignments from a local stonith device and
  the fencing agent availability
* `list-status`: same as `list` but with the status of each assignement
* `validate-all`: validate the configuration of the resource
* `meta-data`: displays the capabilities of the agent for the cluster
* `manpage`: displays the name of the man page for this fencing agent

:::

-----

### Practical work: Fencing

::: notes

FR Au cours de workshop, nous utilisons l'agent de fencing `fence_virsh`. Il ne
FR fait pas parti des agents de fencing distribués par défaut et s'installe via le
FR paquet `fence-agents-virsh`. Cet agent de fencing est basé sur SSH et la
FR commande `virsh`.
FR
FR 1. installer tous les _FA_ ainsi que `fence_virsh`
FR 2. lister les FA à l'aide de `pcs resource` ou `stonith_admin`
FR
FR Nous abordons la création d'une ressource de fencing plus loin dans le workshop.
FR
During this worshop, we will use the fencing agent `fence_virsh`. it's not part
of the default fencing agent package and can be installed via the package
`fence-agent-virsh`. This fencing agent is based on SSH and the `virsh`
command.

1. install all the _FA_ including `fence_virsh`
2. list the _FA_ with `pcs resource` and `stonith_admin`

We will delve into fencing resource creation later on.

:::

-----

### Correction: Fencing

::: notes

FR 1. installer tous les _FA_ ainsi que `fence_virsh`
FR
1. install all the _FA_ including `fence_virsh`

~~~console
# yum install -y fence-agents-all fence-agents-virsh
~~~

FR 2. lister les FA à l'aide de `pcs resource` ou `stonith_admin`
FR
2. list the _FA_ with `pcs resource` and `stonith_admin`

~~~
# pcs resource agents stonith
fence_amt_ws
fence_apc
fence_apc_snmp
[...]

# stonith_admin --list-installed
 fence_xvm
 fence_wti
 fence_vmware_soap
[...]
~~~

:::

-----

## `LRMd` et _Resources Agent_ - Global diagram

![LRM and it's resources diagram](medias/pcmk-archi-resource.png)

-----

### Local Resource Manager (LRM)

FR * daemon `lrmd`
FR * interface entre le `CRMd` et les _resource agents_ (_RA_)
FR * capable d'exécuter les différents types de _RA_ supportés (OCF, systemd,
FR   LSF, etc) et d'en comprendre la réponse
FR * reçoit des commandes du `CRMd` et les passe aux _RA_
FR * renvoie le résultat de l'action au `CRMd` de façon homogène, quelque
FR   soit le type de _RA_ utilisé
FR * est responsable d'exécuter les actions récurrentes en toute autonomie et de
FR   prévenir le `CRMd` en cas d'écart avec le résultat attendu
FR * renommé _local executor_ depuis la version 2.0
FR
* `LRMd` daemon
* interface between `CRMd` and the _resource agent_ (_RA_)
* can inteface with all the available _RA_ types (OCF, systemd, LSF, etc.) and
  understand their answers
* receives `CRMd` commands and feeds them to _RA_
* resends the result of the action to `CRMd` in a homogenous fashion despite
  the _RA_ type
* is responsible for the execution of recurring actions and must warn `CRMd` in
  case the result of the action is different from the expected one (e.g.
  monitor)
* renamed 'local executor' in version 2.0

::: notes

<!-- c'est le CRMd DC qui met a jour la CIB ? avec les codes retour ? -->
FR Lorsqu'une instruction doit être transmise à un agent, le `CRMd` passe
FR cette information au `LRMd`, qui se charge de faire exécuter l'action
FR appropriée par le _RA_.
FR
FR Le daemon `LRMd` reçoit un code de retour de l'agent, qu'il transmet au
FR `CRMd`, lequel mettra à jour la CIB pour que cette information soit
FR partagée au niveau du cluster.
FR
FR Pour les actions dont le paramètre `interval` est supérieur à 0, le
FR `LRMd` est responsable d'exécuter les actions de façon récurrente
FR à la période indiquée dans la configuration. Le `LRMd` ne
FR reviendra vers le `CRMd` que si le code retour de l'action varie.
FR
When an instruction must be sent to an agent, `CRMd` sends the information to
`LRMd` which execute the appropriate action on the _RA_.

The `LRMd` daemon receives the return code from the agent and transmits it to
`CRMd` which is tasked with updating the CIB so that the whole cluster is aware
of the result.

For action where the `interval` parameter is superior to 0, `LRMd` is
responsible for their recurring execution once the period specified in the
configuration has ended. `LRMd` will get back to `CRMd` in case the return code
is not the expected one.

:::

-----

### _Ressource Agent_ (_RA_)

FR * applique les instructions du `LRMd` sur la ressource qu'il gère
FR * renvoie des codes retours stricts reflétant le statut de sa ressource
FR * plusieurs types/API de _ressource agent_ supportés
FR * la spécification "OCF" est la plus complète
FR * l'API OCF présente au `CRMd` les actions supportées par l'agent
FR * `action` et `operation` sont deux termes synonymes
FR * chaque opérations a un timeout propre et éventuellement une récurrence
FR
* applies the instruction sent by `LRMd` on the resource it manages
* resends the return code according to the API specification, in accordance to
  the resource status
* several kinds of _resource agent_ supported (with different API)
* the _OCF_ specification is the most exhaustive
* the _OCF_ API present the action supported by the agent to `CRMd`
* `action` and `operation` as synonyms
* each operation has a specific timeout and might have an inteval for recuring
  operations
 
::: notes

FR Il est possible d'utiliser plusieurs types de _RA_ différents au sein d'un même cluster:
FR
FR * OCF (Open Cluster Framework, type préconisé)
FR * SYSV
FR * systemd...
FR
FR Vous trouverez la liste des types supportés à l'adresse suivante:
FR <https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/s-resource-supported.html>
It's possible to use several kinfs of _RA_ in the same cluster:

* OCF (Open ClusterFramework, the advised type)
* SYSV
* Systemd
* etc..

A list of all available types of _RA_ is available here:
<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/s-resource-supported.html>

FR Dans les spécifications du type OCF, un agent a le choix parmi dix codes retours
FR différents pour communiquer l'état de son opération à `LRMd`:
FR

In the _OCF_ specification, ten different return codes are available for the
_RA_ to communicate the state of the action it was tasked with by `LMRd`.

* `OCF_SUCCESS` (0, soft)
* `OCF_ERR_GENERIC` (1, soft)
* `OCF_ERR_ARGS` (2, hard)
* `OCF_ERR_UNIMPLEMENTED` (3, hard)
* `OCF_ERR_PERM` (4, hard)
* `OCF_ERR_INSTALLED` (5, hard)
* `OCF_ERR_CONFIGURED` (6, fatal)
* `OCF_NOT_RUNNING` (7)
* `OCF_RUNNING_MASTER` (8, soft)
* `OCF_FAILED_MASTER` (9, soft)

FR Chaque code retour est associé à un niveau de criticité s'il ne correspond
FR à celui attendu par le cluster:
FR
FR * `soft`: le cluster tente une action corrective sur le même nœud ou déplace
FR   la ressource ailleurs
FR * `hard`: la ressource doit être déplacée et ne pas revenir sur l'ancien nœud
FR   sans intervention humaine
FR * `fatal`: le cluster ne peut gérer la ressource sur aucun nœud
FR
Each return code as a corresponding criticity, which is used when the return
code is different from the one expected by the cluster:

* `soft`: the cluster will try to make a corrective action on the same node or
  move the resource elsewhere;
* `hard`: the resource must be move and cannot return to the old node without
  human intervention;
* `fatal`: the cluster cannot  manage the resource on any node.

FR Voici les opérations disponibles aux agents implémentant la specification OCF:
FR
FR * `start`: démarre la ressource
FR * `stop`: arrête la ressource
FR * `monitor`: vérifie l'état de la ressource
FR * `validate-all`: valide la configuration de la ressource
FR * `meta-data`: présente les capacités de l'agent au cluster
FR * `promote`: promote la ressource slave en master
FR * `demote`: démote la ressource master en slave
FR * `migrate_to`: actions à réaliser pour déplacer une ressource vers un autre nœud
FR * `migrate_from`: actions à réaliser pour déplacer une ressource vers le nœud local
FR * `notify`: action à exécuter lorsque le cluster notifie l'agent des actions
FR   le concernant au sein du cluster
FR
These are the available operations for the agent who implement the _OCF_
specification:

* `start`: start the resource
* `stop`: stop resource
* `monitor`: check the state resource
* `validate-all`: validate the configuration of the resource
* `meta-data`: displays the capabilities of the _RA_
* `promote`: promote the slave resource into a master
* `demote`: demote a master resource to a slave
* `migrate_to`: required action in order to move the resource to another node
* `migrate_from`: required action in order to move the resource to the local
  node
* `notify`: action to execute when the cluster notifies the _RA_ of the actions
  it must execute

FR L'opération `meta-data` permet à l'agent de documenter ses paramètres et
FR d'exposer ses capacités au cluster qui adapte donc ses décisions en fonction
FR des actions possibles. Par exemple, si les actions `migrate_*` ne sont pas
FR disponibles, le cluster utilise les actions `stop` et `start` pour déplacer
FR une ressource.
FR
The `meta-data` operation is used by the agent to document it's configuration
and expose it's capabilities to the cluster. The cluster will then adapt it's
decision according to the available actions. For example, if the `migrate_*`
action are not available, the cluster will use the `stop` and `start` actions
to move a resource.

FR Les agents systemd ou sysV sont limités aux seules actions `start`, `stop`,
FR `monitor`. Dans ces deux cas, les codes retours sont interprétés par `LRMd`
FR comme étant ceux définis par la spécification LSB:
FR <http://refspecs.linuxbase.org/LSB_3.0.0/LSB-PDA/LSB-PDA/iniscrptact.html>
FR
The systemd and sysV agent are limited to three actions `start`, `stop` and
`monitor`. With these agents `LRMd` interprets the return codes as described in
the LSB specification:
<http://refspecs.linuxbase.org/LSB_3.0.0/LSB-PDA/LSB-PDA/iniscrptact.html>

FR Un ressource peut gérer un service seul (eg. une vIP) au sein du cluster, un
FR ensemble de service cloné (eg. Nginx) ou un ensemble de clone _multi-state_
FR pour lesquels un statut `master` et `slave` est géré par le cluster et le _RA_.
FR
A resource can manage a single service (e.g. a VIP), or a group of cloned
services (e.g. Nginx) or even a group of _multi-state_ clones where the
`master` and `slave` state is managed by the cluster and the _RA_.

FR Les _RA_ qui pilotent des ressources _multi-state_ implémentent obligatoirement
FR les actions `promote` et `demote` : une ressource est clonée sur autant de
FR nœuds que demandé, démarrée en tant que slave, puis le cluster promeut un ou
FR plusieurs `master` parmi les `slave`.
FR
The _RA_ designed to control _multi-state_ resources must implement the
`promote` and `demote` actions: the resource will be cloned on as many nodes as
requested, started as a slave, then the cluster will promote one or several
`masters` amongst the `slaves`.

FR Le _resource agent_ PAF utilise intensément toutes ces actions, sauf
FR `migrate_to` et `migrate_from` qui ne sont disponibles qu'aux _RA_ non
FR _multi-state_ (non implémenté dans Pacemaker pour les ressources multistate).
FR
The _resource agent_ PAF uses all theses actions except for `migrate_to` and
`migrate_from` which are available only for non _multi-state_ _RA_ (it's not
implemented in Pacemaker for multi state resources).

:::

-----

### Practical Work: _Resource Agents_

::: notes

FR 1. installer les _resource agents_
FR 2. lister les RA installés à l'aide de `pcs`
FR 3. afficher les informations relatives à l'agent `dummy` à l'aide de `pcs`
FR 4. afficher les informations relatives à l'agent `pgsql` à l'aide de `pcs`
FR
1. install the _resource agents_
2. list the available _RA_ with `pcs`
3. display the information about the `dummy` _RA_ with `pcs`
4. display the information about the `pgsql` _RA_ with `pcs`

:::

-----

### Correction: _Resource Agents_

::: notes

FR 1. installer les _resource agents_
FR
FR Il est normalement déjà installé comme dépendance de pacemaker.
FR
1. install the _resource agents_

This package is usually installed as a dependency of Pacemaker.

~~~
yum install -y resource-agents
~~~

FR 2. lister les RA installés à l'aide de `pcs`
FR
2. list the available _RA_ with `pcs`

~~~
pcs resource agents
~~~

FR 3. afficher les informations relatives à l'agent `dummy` à l'aide de `pcs`
FR
FR Chaque agent embarque sa propre documentation.
FR
3. display the information about the `dummy` _RA_ with `pcs`

Each _RA_ contains it's own documentation.

~~~
pcs resource describe dummy
~~~

FR 4. afficher les informations relatives à l'agent `pgsql` à l'aide de `pcs`
FR
FR Le RA `pgsql` livré avec le paquet `resource-agents` n'est **pas** celui de PAF. Vous
FR pouvez lister l'ensemble de ses options grâce à la commande:
FR

4. display the information about the `pgsql` _RA_ with `pcs`

The `pgsql` _RA_ is deployed with the `resource_agents` package is the one
deployed with PAF.

You can list all it's options with the command :

~~~
pcs resource describe pgsql
~~~

:::

-----

## PostgreSQL Automatic Failover (PAF)

FR * _RA_ spécifique à PostgreSQL pour Pacemaker
FR * alternative à l'agent existant
FR   * moins complexe et moins intrusif
FR   * compatible avec PostgreSQL 9.3 et supérieur
FR * Voir: <https://clusterlabs.github.io/PAF/FAQ.html>
FR
* _RA_ dedicated to PostgreSQL
* an alternative to the existing one
  - less complex and intrusive
  - compatible with PostgreSQL 9.3 and up
* see: <https://clusterlabs.github.io/PAF/FAQ.html>

::: notes

FR PAF se situe entre Pacemaker et PostgreSQL. C'est un _resource agent_
FR qui permet au cluster d'administrer pleinement une instance PostgreSQL locale.
FR
FR Un chapitre entier est dédié à son installation, son fonctionnement et sa
FR configuration plus loin dans ce workshop.
FR
FR ![Schema](medias/pcmk-archi-paf-overview.png)
FR
PAF is a component placed between Pacemaker and PostgreSQL. It's a _resource
agent_ which enables the cluster to administer a local PostgreSQL instance.

A chapter dedicated to it's installation, inner working and configuration can
be found later in this workshop.

![Schema](medias/pcmk-archi-paf-overview.png)
:::

------

# Paramétrage du cluster

Attention:

* les paramètres de Pacemaker sont tous sensibles à la casse
* aucune erreur n'est levée en cas de création d'un paramètre inexistant
* les paramètres inconnus sont simplement ignorés par Pacemaker

-----

## Support du Quorum

Paramètre `no-quorum-policy`

* `ignore`: désactive la gestion du quorum (déconseillé !)
* `stop`: (par défaut) arrête toutes les ressources
* `freeze`: préserve les ressources encore disponible dans la partition
* `suicide`: fencing des nœuds de la partition

:::notes

Il est fortement déconseillé de désactiver le quorum.

La valeur par défaut est le plus souvent la plus adaptée.

Le cas du `freeze` peut être utile afin de conserver les ressources actives au
sein d'un cluster où il n'y a aucun risque de split brain en cas de partition
réseau, eg. un serveur httpd.

:::

-----

## Support du Stonith

Paramètre `stonith-enabled`

* `false` : désactive la gestion du fencing (déconseillé !)
* activé par défaut
* aucune ressource ne démarre sans présence de FA

:::notes

Ce paramètre contrôle la gestion du fencing au sein du cluster. Ce dernier
est activé et il est vivement recommandé de ne pas le désactiver.

Effectivement, il est possible de désactiver le fencing au cas par cas,
ressource par ressource, grâce à leur méta-attribut `requires` (voir
chapitre [Configuration des ressources][]), positionné par défaut à `fencing`.


Il est techniquement possible de désactiver le [quorum][] ou [fencing][].

Comme dit précédemment c'est à proscrire hors d'un environnement de test. Sans
ces fonctionnalités, le comportement du cluster est imprévisible en cas de
panne et sa cohérence en péril.

Dans le cas d'un cluster qui gère une base de donnée cela signifie que l'on encourt le
risque d'avoir plusieurs ressources PostgreSQL disponibles en écriture sur plusieurs
nœuds (conséquence d'un `split brain`).

:::

-----

## Cluster symétrique et asymétrique

Paramètre `symmetric-cluster`:

* change l'effet des scores de préférence des ressources
* `true`: (par défaut) cluster symétrique ou _Opt-Out_. Les ressources
  peuvent démarrer sur tous les nœuds à moins d'y avoir un score déclaré
  inférieur à `0`
* `false`: cluster asymétrique ou _Opt-In_. Les ressources ne peuvent
  démarrer sur un nœud à moins  d'y avoir un score déclaré supérieur ou
  égal à `0`

::: notes

Le paramètre `symetric-cluster` permet de changer la façon dont pacemaker choisit
où démarrer les ressources.

Configuré à `true` (defaut), le cluster est dit symétrique. Les ressources
peuvent être démarrées sur n'importe quel nœud. Le choix se fait par ordre
décroissant des valeurs des [contraintes de localisation][Scores etlocalisation].
Une contrainte de localisation négative empêchera la ressource de démarrer
sur un nœud.

Configuré à `false`, le cluster est dit asymétrique. Les ressources ne peuvent
démarrer nulle part. La définition des contraintes de localisation doit définir
sur quels nœuds les ressources peuvent être démarrées.

La notion de contraintes de localisation est définie dans le chapitre
[Contraintes de localisation][]

:::

-----

## Mode maintenance

Paramètre `maintenance-mode`:

* désactive tout contrôle du cluster
* plus aucun opération n'est exécutée
* plus de monitoring des ressources
* les ressources démarrée sont laissée dans leur état courant (elles ne
  sont pas arrêtées)
* toujours tester les transitions avec `crm_simulate` avant de sortir de la
  maintenance

::: notes

Le paramètre `maintenance_mode` est utile pour réaliser des opérations de
maintenance globales à tous les nœuds du cluster. Toutes les opérations
`monitor` sont désactivées et le cluster ne réagit plus aucun événements.

Ce paramètre, comme tous les autres, est préservé lors du redémarrage de
Pacemaker, sur un ou tous les nœuds. Il est donc possible de redémarrer tout
le cluster tout en conservant le mode maintenance actif.

Attention toutefois aux scores de localisation. D'autant plus que ceux-ci
peuvent être mis à jour lors du démarrage du cluster sur un nœud par exemple.
Vérifiez toujours que les ressources sont bien dans l'état attendu sur chaque
nœud avant de sortir du mode de maintenance afin d'éviter une intervention du
cluster. Lorsque ce dernier reprend la main, il lance l'action `probe` sur
toutes les ressources sur tous les nœuds pour détecter leur présence et
comparer la réalité avec l'état de sa CIB.

:::

-----

## Autres paramètres utiles

* `stop-all-resources=false`: toutes les ressources sont arrêtées si
  positionné à `true` 
* `stonith-watchdog-timeout`: temps d'attente avant qu'un nœud disparu est
  considéré comme "auto-fencé" par son watchdog si le cluster est configuré
  avec
* `cluster-recheck-interval=15min`: intervalle entre deux réveils forcé du
  `PEngine` pour vérifier l'état du cluster

::: notes

Pour la liste complète des paramètres globaux du cluster, voir:

<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/s-cluster-options.html>

:::

-----

## TP: paramètres du cluster

::: notes

1. afficher les valeurs par défaut des paramètres suivants à l'aide de `pcs property`:

  * `no-quorum-policy`
  * `stonith-enabled`
  * `symmetric-cluster`
  * `maintenance-mode`

:::

-----

## Correction: paramètres du cluster

::: notes

1. afficher les valeurs par défaut des paramètres suivants à l'aide de `pcs property`:

  * `no-quorum-policy`
  * `stonith-enabled`
  * `symmetric-cluster`
  * `maintenance-mode`


~~~console
# pcs property list --defaults|grep -E "(no-quorum-policy|stonith-enabled|symmetric-cluster|maintenance-mode)"
 maintenance-mode: false
 no-quorum-policy: stop
 stonith-enabled: true
 symmetric-cluster: true
~~~

:::

-----

# Attributs d'un nœud

## Généralité sur les attributs d'un nœud

* attributs propres à chaque nœud
* peut être persistant après reboot ou non
* peut stocker n'importe quelle valeur sous n'importe quel nom
* eg. `kernel=4.19.0-8-amd64`

::: notes

Il est possible de créer vos propres attributs avec l'outil `crm_attribute`.

La persistance de vos attributs se contrôle avec l'argument `--lifetime`:

* valeur réinitialisée au redémarrage (non persistant) : `--lifetime reboot`
  * note : `--type status` est également accepté. Mentionné dans la
    documentation mais pas dans le manuel de la commande 
* valeur conservée au redémarrage (persistant) : `--lifetime forever`
  * note : `--type nodes` est également accepté. Mentionnée dans la
    documentation mais pas dans le manuel de la commande 

Exemple pour stocker dans un attribut du nœud nommé `kernel` la version du
noyau système :

~~~
crm_attribute -l forever --node hanode1 --name kernel --update $(uname -r)
~~~

Exemple de l'utilisation d'une rule basée sur un attribut de ce type:
<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/_using_rules_to_determine_resource_location.html#_location_rules_based_on_other_node_properties>

Le _RA_ PAF utilise également les attributs non persistants et très
transitoires. À l'annonce d'une promotion, chaque esclave renseigne son LSN
dans un attribut transient. Lors de la promotion, le nœud "élu" compare son LSN
avec celui des autres nœuds en consultant leur attribut `lsn_location` pour
s'assurer qu'il est bien le plus avancé. Ces attributs sont détruits une fois
l'élection terminée.

:::

-----

## Attributs de nœuds spéciaux

* plusieurs attributs font office de paramètres de configuration
* `maintenance`: mode maintenance au niveau du nœud
* `standby`: migrer toutes les ressources hors du nœud

::: notes

Il existe plusieurs attributs de nœuds spéciaux qui font offices de
paramétrage. Les deux plus utiles sont `maintenance` et `standby`.

L'attribut `maintenance` a le même effet que le `maintenance_mode` au niveau
du cluster, mais localisé au seul nœud sur lequel il est activé.

Lorsque l'attribut `standby` est activé, il indique que le nœud ne doit plus
héberger aucune ressource. Elle sont alors migré vers d'autres nœuds ou
arrêté le cas échéant.

Vous trouverez la liste complète de ces attributs de nœud spéciaux à
l'adresse suivante:
<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/_special_node_attributes.html>

:::

-----

## Attributs de nœuds particuliers

Quelques autres attributs particuliers:

* `fail-count-*`: nombre d'incident par ressource sur le nœud
* `master-*`: _master score_ de la ressource sur le nœud

::: notes

Un attribut `fail-count-*` de type non persistant est utilisés pour
mémoriser le nombre d'erreur de chaque ressources sur chaque nœud. Préférez
utiliser `crm_failcount` ou `pcs resource failcount` pour accéder à ces
informations.

Enfin, il existe des _master score_ pour les ressources de type _multi-state_
(primaire/secondaire), permettant d'indiquer où l'instance primaire peut ou
doit se trouver dans le cluster. Il sont préfixé par `master-*`. PAF positionne
ces scores comme attributs persistants des nœuds. La position de l'instance
primaire est ainsi préservée lors du redémarrage du cluster.

Vous pouvez consulter ou modifier les _master score_ à l'aide de l'outil
`crm_master`. Attention toutefois, ces scores sont positionnés habituellement
par le _RA_ lui même. À moins de vous trouver dans une situation où le
cluster ne nomme aucune ressource primaire, vous ne devriez pas vous même
positionner un _maser score_.

:::

-----

# Configuration des ressources

* mécanique interne
* __tout__ dépend des scores !
* chapitre organisé dans l'ordre des besoins de configuration

-----

## Méta-attributs des ressources

* un ensemble de _meta-attributes_ s'appliquent à n'importe quelle ressource:
  * il est possible de leur positionner une valeur par défaut qui s'applique
    à toutes les ressources
  * il est possible de surcharger les valeurs par défaut pour chaque ressource
* quelques exemple de méta-attributs:
  * `target-role`: rôle attendu: `Started`, `Stopped`, `Slave`, ou `Master`
  * `migration-threshold` : combien d'erreurs "soft" avant de déclencher un failover
  * `failure-timeout` : durée à partir de laquelle les erreurs "soft" sont réinitialisées
  * `resource-stickiness` : score de maintien d'une ressource sur le nœud courant
  * `is-managed`: le cluster doit-il agir en cas d'événement ?

::: notes

Les _meta-attributes_ est un ensemble d'attributs commun à n'importe quelle
type de ressource. Ils se positionnent ressource par ressource. Il est possible
de leur créer une valeur par défaut qui sera appliquée automatiquement à toute
ressource présente dans le cluster.

Par exemple avec `pcs`:

~~~
pcs resource defaults <nom_attribut>=valeur
~~~

Le même exemple avec l'outil standard `crm_attribute`:

~~~
crm_attribute --type rsc_defaults --name <nom_attribut> --update valeur
~~~

La valeur d'un méta attribut positionné au niveau de la ressource elle même
surcharge la valeur par défaut positionné précédemment.

La liste complète des méta-attributs et leur valeur par défaut est disponible à
cette adresse:
<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/s-resource-options.html#_resource_meta_attributes>

:::

-----

### TP: paramétrage par défaut des ressources

::: notes

1. trouver la valeur par défaut du paramètre `migration-threshold`
2. positionner sa valeur à dix
3. supprimer la valeur par défaut du paramètre `is-managed`
4. contrôler que les modifications sont prise en compte avec `pcs config show`
5. observer les modifications de la CIB dans les logs

Remarque: il existe une propriété du cluster `default-resource-stickiness`.
Cette propriété est dépréciée, il faut utiliser les valeurs par defaut des
ressources à la place.

~~~
pcs property list --defaults |grep -E "resource-stickiness"
 default-resource-stickiness: 0
~~~

:::

-----

### Correction: paramétrage par défaut des ressources

::: notes

1. trouver la valeur par défaut du paramètre `migration-threshold`

La valeur par défaut est `INFINITY`. Voir:

<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/s-resource-options.html#_resource_meta_attributes>

2. positionner sa valeur à dix

~~~console
# pcs resource defaults migration-threshold=10
Warning: Defaults do not apply to resources which override them with their own defined values
# pcs resource defaults
migration-threshold: 10
~~~

3. supprimer la valeur par défaut du paramètre `is-managed`

~~~console
# pcs resource defaults is-managed=
Warning: Defaults do not apply to resources which override them with their own defined values
~~~

4. contrôler que les modifications sont prise en compte avec `pcs config show`

~~~
# pcs config show
[...]
Resources Defaults:
 migration-threshold=10
[...]
~~~

5. observer les modifications de la CIB dans les logs

NB: les log ont ici été remis en forme.

~~~
cib: info: Forwarding cib_apply_diff operation for section 'all' to all
cib: info: Diff: --- 0.5.5 2
cib: info: Diff: +++ 0.6.0 2edcd42b63c34c8c39f2ab281d0c09b8
cib: info: +  /cib:  @epoch=6, @num_updates=0
cib: info: ++ /cib/configuration:
cib: info: ++ <rsc_defaults/>
cib: info: ++   <meta_attributes id="rsc_defaults-options">
cib: info: ++     <nvpair id="..." name="migration-threshold" value="3"/>
cib: info: ++   </meta_attributes>
cib: info: ++ </rsc_defaults>
cib: info: Completed cib_apply_diff operation for section 'all': OK
~~~

:::

-----

## Configuration du fencing

* les _FA_ sont gérés comme des ressources classiques
* les _FA_ ont un certain nombre de paramètres en commun: `pcmk_*`
* les autres paramètres sont propres à chaque _FA_, eg. `port`, `identity_file`, `username`, ...
* chaque _FA_ configuré peut être appelé de n'importe quel nœud

::: notes

Pour chaque agent de fencing configuré, un certain nombre de méta attributs
définissent les capacités de l'agent auprès du cluster. Quelque exemples
notables:

* `pcmk_reboot_action`: détermine quelle action exécuter pour isoler un nœud.
  Par exemple `reboot` ou `off`. L'action indiquée dépend de ce que supporte
  l'agent
* `pcmk_host_check`: détermine si l'agent doit interroger l'équipement pour
  établir la liste des nœuds qu'il peut isoler, ou s'il doit se reposer sur
  le paramètre `pcmk_host_list`
* `pcmk_host_list`: liste des nœuds que peut isoler l'agent de fencing
* `pcmk_delay_base`: temps d'attente minimum avant de lancer l'action de
  fencing. Pratique dans les cluster à deux nœuds pour privilégier un des
  nœuds

ous trouverez la liste complète à l'adresse suivante:
<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/_special_options_for_fencing_resources.html>

Tous les paramètres ne débutants pas par `pcmk_*` sont propres à chaque
_fencing agent_. Dans le cadre de notre workshop, nous utiliserons l'agent
`fence_virsh` qui nécessite des paramètres de connexion SSH ainsi que le nom
de la machine virtuelle à interrompre.

Une fois paramétrés, Pacemaker s'assure que les _FA_ restent disponibles en
exécutant à intervalle régulier l'action `monitor`, positionnée par défaut
à une minute. À cause de cette action récurrente, les _FA_ apparaissent au
sein du cluster au même titre que les autres ressources. Mais notez qu'une
ressource de fencing ne démarre pas sur les nœud du cluster, ces équipement
sont actifs _ailleurs_ dans votre architecture.

Lorsqu'une action de fencing commandée par Pacemaker, celle-ci sera déclenchée
en priorité depuis le nœud d'où la ressource est supervisée. Si le nœud ou
la ressource de fencing sont devenus indisponibles depuis la dernière action de
monitor, n'importe quel autre nœud du cluster peut être utilisé pour
exécuter la commande.

:::

-----

### TP: Fencing Agent

::: notes

Rappel: par défaut le cluster refuse de prendre en charge des ressources en HA sans
fencing configuré.

~~~console
# crm_verify --verbose --live-check
~~~

1. afficher la description de l'agent de fencing `fence_virsh`

Nous allons utiliser les paramètres suivants:

* `ipaddr`: adresse de l'hyperviseur sur lequel se connecter en SSH
* `login`: utilisateur SSH pour se connecter à l'hyperviseur
* `identity_file`: chemin vers la clé privée SSH à utiliser pour l'authentification
* `login_timeout`: timeout du login SSH
* `port`: nom de la VM à isoler dans libvirtd

Les autres paramètres sont décrits dans le slide précédent.

Bien s'assurer que chaque nœud peut se connecter en SSH sans mot de passe à
l'hyperviseur.

2. créer une ressource de fencing pour chaque nœud du cluster

Les agents de fencing sont des ressources en HA prises en charge par le
cluster. Dans le cadre de ce TP, nous créons une ressource par nœud,
chacune responsable d'isoler un nœud.

3. vérifier que le cluster ne présente plus d'erreur
4. vérifier que ces ressources ont bien été créées et démarrées
5. afficher la configuration des agents de fencing
6. vérifier dans les log que ces ressources sont bien surveillée par `LRMd`

:::

-----

### Correction: Fencing Agent

::: notes

Rappel: par défaut le cluster refuse de prendre en charge des ressources en HA sans
fencing configuré.

~~~console
# crm_verify --verbose --live-check
   error: unpack_resources:	Resource start-up disabled since no STONITH resources have been defined
   error: unpack_resources:	Either configure some or disable STONITH with the stonith-enabled option
   error: unpack_resources:	NOTE: Clusters with shared data need STONITH to ensure data integrity
Errors found during check: config not valid
~~~


1. afficher la description de l'agent de fencing `fence_virsh`

~~~
# pcs resource describe stonith:fence_virsh
~~~

2. créer une ressource de fencing pour chaque nœud du cluster

Adapter `pcmk_host_list`, `ipaddr`, `login` et `port` à votre environnement.

~~~console
# pcs stonith create fence_vm_hanode1 fence_virsh pcmk_host_check="static-list" \
pcmk_host_list="hanode1" ipaddr="10.20.30.1" login="user"                       \
port="centos7_hanode1" pcmk_reboot_action="reboot"                              \
identity_file="/root/.ssh/id_rsa" login_timeout=15

# pcs stonith create fence_vm_hanode2 fence_virsh pcmk_host_check="static-list" \
pcmk_host_list="hanode2" ipaddr="10.20.30.1" login="user"                       \
port="centos7_hanode2" pcmk_reboot_action="reboot"                              \
identity_file="/root/.ssh/id_rsa" login_timeout=15

# pcs stonith create fence_vm_hanode3 fence_virsh pcmk_host_check="static-list" \
pcmk_host_list="hanode3" ipaddr="10.20.30.1" login="user"                       \
port="centos7_hanode3" pcmk_reboot_action="reboot"                              \
identity_file="/root/.ssh/id_rsa" login_timeout=15
~~~

3. vérifier que le cluster ne présente plus d'erreur

~~~console
# crm_verify -VL
# echo $?
0
~~~

4. vérifier que ces ressources ont bien été créées et démarrées

~~~console
# pcs status
[...]
3 nodes configured
3 resources configured

Online: [ hanode1 hanode2 hanode3 ]

Full list of resources:

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode3
[...]
~~~

5. afficher la configuration des agents de fencing

~~~
# pcs stonith show --full
 Resource: fence_vm_hanode1 (class=stonith type=fence_virsh)
  Attributes: identity_file=/root/.ssh/id_rsa ipaddr=10.20.30.1 login=ioguix login_timeout=15 pcmk_host_check=static-list pcmk_host_list=hanode1 pcmk_reboot_action=reboot port=paf_3n-vip_hanode1
  Operations: monitor interval=60s (fence_vm_hanode1-monitor-interval-60s)
 Resource: fence_vm_hanode2 (class=stonith type=fence_virsh)
  Attributes: identity_file=/root/.ssh/id_rsa ipaddr=10.20.30.1 login=ioguix login_timeout=15 pcmk_host_check=static-list pcmk_host_list=hanode2 pcmk_reboot_action=reboot port=paf_3n-vip_hanode2
  Operations: monitor interval=60s (fence_vm_hanode2-monitor-interval-60s)
 Resource: fence_vm_hanode3 (class=stonith type=fence_virsh)
  Attributes: identity_file=/root/.ssh/id_rsa ipaddr=10.20.30.1 login=ioguix login_timeout=15 pcmk_host_check=static-list pcmk_host_list=hanode3 pcmk_reboot_action=reboot port=paf_3n-vip_hanode3
  Operations: monitor interval=60s (fence_vm_hanode3-monitor-interval-60s)
~~~

6. vérifier dans les log que ces ressources sont bien surveillée par `LRMd`

Les log ont été remis en forme.

~~~
lrmd: debug: executing - rsc:fence_vm_hanode1 action:monitor call_id:7
lrmd: debug: finished - rsc:fence_vm_hanode1 action:monitor call_id:7  exit-code:0
crmd:  info: Result of monitor operation for fence_vm_hanode1 on hanode1: 0 (ok) 
~~~

:::

-----

## Scores et contrainte localisation

* pondération interne d'une ressource sur un nœud
* peut définir une exclusion si le score est négatif
* `stickiness` : score de maintien en place d'une ressource sur son nœud
  actuel
* éviter d'exclure un agent de fencing de son propre nœud définitivement
* scores accessibles grâce à `crm_simulate`

::: notes

Pacemaker se base sur la configuration et les scores des ressources pour
calculer l'état idéal du cluster. Le cluster choisi le nœud où une ressource à
le score le plus haut pour l'y placer.

Les scores peuvent être positionnés comme:

* contraintes de localisation ;
* [contraintes de colocation][Contraintes de colocation] ;
* attributs:
  * [`resource-stickiness`][Méta-attributs des ressources] du cluster ou des
    ressources ;
  * [`symetric-cluster`][Cluster symétrique et asymétrique] du cluster ;

Ils sont aussi être manipulés tout au long de la vie du cluster. Eg.:

* [bascule][Détail d'un switchover] effectuée par l'administrateur :
  * ban : place un score de localisation de `-INFINITY` sur le nœud courant ;
  * move : place un score de localisation de `+INFINITY` sur le nœud cible ;
* les ressources agents pour désigner l'instance primaire grâce à un score de
  localisation du rôle `master`.

Si pacemaker n'a pas d'instruction ou si les contraintes de localisation ont le
même score alors pacemaker tente de répartir équitablement les ressources parmi
les nœuds candidats. Ce comportement peut placer vos ressource de façon plus ou
moins aléatoire. Un score négatif empêche le placement d'une ressource sur un nœud.

Les scores `+INFINITY` et `-INFINITY` permettent de forcer une ressource à
rejoindre ou quitter un nœud de manière inconditionnelle. Voici l'arithmétique
utilisée avec `INFINITY`:

~~~
INFINITY =< 1000000
Any value + INFINITY = INFINITY
Any value - INFINITY = -INFINITY
INFINITY - INFINITY = -INFINITY
~~~

Si un nœud est sorti momentanément du cluster, par défaut ses ressources sont
déplacées vers d'autres nœuds. Lors de sa réintroduction, les contraintes de
localisation définies peuvent provoquer une nouvelle bascule des ressources si
les scores y sont supérieurs ou égaux à ceux présents sur les autres nœuds. La
plus part du temps, il est préférable d'éviter de déplacer des ressources qui
fonctionnent correctement. C'est particulièrement vrai pour les base de données
dont le temps de bascule peut prendre plusieurs secondes.

Le paramètre `stickiness` permet d'indiquer à pacemaker à quel point une
ressource en bonne santé préfère rester où elle se trouve. Pour cela la valeur
du paramètre `stickiness` est additionnée au score de localisation de la
ressource sur le nœud courant et comparé aux scores sur les autres nœuds pour
déterminer le nœud "idéal". Ce paramètre peut être défini globalement ou par
ressource.

Les scores de localisation sont aussi utilisés pour positionner les ressources
de fencing. Vous pouvez les empêcher d'être exécutées depuis un nœud en
utilisant un score d'exclusion de `-INFINITY`. Cette ressource ne sera alors ni
supervisée, ni exécutée depuis ce nœud. Une telle configuration est souvent
utilisée pour empêcher une ressource de fencing d'être priorisée ou déclenchée
depuis le nœud qu'elle doit isoler. Néanmoins, il n'est pas recommandé
d'empêcher ce comporter à tout prix. Un score négatif reste une bonne
pratique, mais il est préférable d'autoriser le fencing d'un nœud depuis lui
même, en dernier recours.

Enfin, les scores sont consultables grâce à l'outil `crm_simulate`.
:::

-----

### TP: création des contraintes de localisation

::: notes

1. afficher les scores au sein du cluster

Noter quel nœud est responsable de chaque ressource de fencing

2. positionner les stickiness de toutes les ressources à `1`
3. comparer l'évolution des scores
4. ajouter des contraintes d'exclusion pour que chaque ressource de fencing
   évite le nœud dont il est responsable. Utiliser un poids de 100 pour ces
   contraintes.
5. observer les changements de placement et de score par rapport à l'état
   précédent
6. afficher les contraintes existantes à l'aide de `pcs`

:::

-----

### Correction: création des contraintes de localisation

::: notes

1. afficher les scores au sein du cluster

~~~console
# crm_simulate --show-scores --live-check

Current cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode3

Allocation scores:
native_color: fence_vm_hanode1 allocation score on hanode1: 0
native_color: fence_vm_hanode1 allocation score on hanode2: 0
native_color: fence_vm_hanode1 allocation score on hanode3: 0
native_color: fence_vm_hanode2 allocation score on hanode1: 0
native_color: fence_vm_hanode2 allocation score on hanode2: 0
native_color: fence_vm_hanode2 allocation score on hanode3: 0
native_color: fence_vm_hanode3 allocation score on hanode1: 0
native_color: fence_vm_hanode3 allocation score on hanode2: 0
native_color: fence_vm_hanode3 allocation score on hanode3: 0

Transition Summary:
~~~

Ici, `fence_vm_hanode1` est surveillé depuis `hanode1`, `fence_vm_hanode2`
depuis `hanode2` et `fence_vm_hanode3` depuis `hanode3`.

2. positionner les stickiness de toutes les ressources à `1`

~~~console
# pcs resource defaults resource-stickiness=1
~~~

3. comparer l'évolution des scores

~~~console
# crm_simulate -sL
[...]
Allocation scores:
native_color: fence_vm_hanode1 allocation score on hanode1: 1
native_color: fence_vm_hanode1 allocation score on hanode2: 0
native_color: fence_vm_hanode1 allocation score on hanode3: 0
native_color: fence_vm_hanode2 allocation score on hanode1: 0
native_color: fence_vm_hanode2 allocation score on hanode2: 1
native_color: fence_vm_hanode2 allocation score on hanode3: 0
native_color: fence_vm_hanode3 allocation score on hanode1: 0
native_color: fence_vm_hanode3 allocation score on hanode2: 0
native_color: fence_vm_hanode3 allocation score on hanode3: 1
~~~

Le score de chaque ressource a augmenté de `1` pour le nœud sur lequel 
elle est "démarrée".

4. ajouter des contraintes d'exclusion pour que chaque ressource de fencing
   évite le nœud dont il est responsable. Utiliser un poids de 100 pour ces
   contraintes.

~~~console
# pcs constraint location fence_vm_hanode1 avoids hanode1=100
# pcs constraint location fence_vm_hanode2 prefers hanode2=-100
# pcs constraint location fence_vm_hanode3 avoids hanode3=100
~~~

Notez que les deux syntaxes proposées sont équivalentes du point de vue du
résultat dans la CIB.

~~~
# cibadmin -Q --xpath='//rsc_location'
~~~

5. observer les changements de placement et de score par rapport à l'état
   précédent

~~~console
# crm_simulate -sL

Current cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1

Allocation scores:
native_color: fence_vm_hanode1 allocation score on hanode1: -100
native_color: fence_vm_hanode1 allocation score on hanode2: 1
native_color: fence_vm_hanode1 allocation score on hanode3: 0
native_color: fence_vm_hanode2 allocation score on hanode1: 1
native_color: fence_vm_hanode2 allocation score on hanode2: -100
native_color: fence_vm_hanode2 allocation score on hanode3: 0
native_color: fence_vm_hanode3 allocation score on hanode1: 1
native_color: fence_vm_hanode3 allocation score on hanode2: 0
native_color: fence_vm_hanode3 allocation score on hanode3: -100

Transition Summary:
~~~

Chaque ressource a changé de nœud afin de ne plus résider sur celui qu'elle
doit éventuellement isoler.

Un score négatif de `-100` correspondant à la contrainte créée est positionné
pour chaque ressource sur le nœud qu'elle doit éventuellement isoler.

6. afficher les contraintes existantes à l'aide de `pcs`

~~~console
# pcs constraint location show
Location Constraints:
  Resource: fence_vm_hanode1
    Disabled on: hanode1 (score:-100)
  Resource: fence_vm_hanode2
    Disabled on: hanode2 (score:-100)
  Resource: fence_vm_hanode3
    Disabled on: hanode3 (score:-100)

# pcs constraint location show nodes
Location Constraints:
  Node: hanode1
    Not allowed to run:
      Resource: fence_vm_hanode1 (location-fence_vm_hanode1-hanode1--100) Score: -100
  Node: hanode2
    Not allowed to run:
      Resource: fence_vm_hanode2 (location-fence_vm_hanode2-hanode2--100) Score: -100
  Node: hanode3
    Not allowed to run:
      Resource: fence_vm_hanode3 (location-fence_vm_hanode3-hanode3--100) Score: -100

# pcs constraint location show resources fence_vm_hanode1
Location Constraints:
  Resource: fence_vm_hanode1
    Disabled on: hanode1 (score:-100)
~~~

:::

-----

## Création d'une ressource

* nécessite:
  * un identifiant
  * le type/fournisseur/_RA_ à utiliser
* et éventuellement:
  * les paramètres propres à l'agent
  * le paramétrage de [Méta-attributs des ressources]
  * une configuration propre à chaque opérations
* détails sur les timeouts

::: notes

Chaque ressource créée au sein du cluster doit avoir un identifiant unique à
de votre choix.

Vous devez ensuite indiquer le _resource agent_ adapté à la ressource que vous
souhaitez intégrer dans votre cluster. Ce dernier est indiqué dans le format
`type:nom` ou `type:fournisseur:nom`, par exemple: `systemd:pgbouncer`
ou `ocf:heartbeat:Dummy`. La liste complète est disponible grâce à la commande
`pcs resource list`.

Voici un exemple simple de création d'une ressource avec `pcs`:

~~~console
# pcs resource create identifiant_resource type:fournisseur:nom
~~~

Ensuite Chaque _resource agent_ peut avoir des paramètres de configuration
propre à sa ressource, un nom d'utilisateur par exemple. Avec `pcs`, ces
paramètres sont à préciser librement à la suite de la commande de base, par
exemple:

~~~console
# pcs resource create identifiant_resource type:fournisseur:nom \
    user=nom_user_resource
~~~

Pour rappel, la liste des paramètres supportés par un _resource agent_ est
disponible grâce à la commande suivante:

~~~console
# pcs resource describe <agent>
~~~

Comme détaillé dans le chapitre [Méta-attributs des ressources][], les
ressources ont en commun un certain nombre de méta-attributs qui peuvent être
modifiés pour chaque ressource. La commande `pcs` utilise le mot clé `meta`
pour les distinguer sur la ligne de commande des autres paramètres. Par
exemple, nous pouvons positionner `migration-threshold=1` sur une ressource
afin qu'elle soit migrée sur un autre nœud dès la première erreur:

~~~console
# pcs resource create identifiant_resource type:fournisseur:nom \
    user=nom_user_resource                                      \
    meta migration-threshold=1
~~~

Enfin, un certain nombre de paramètres peuvent être modifiés pour chaque
opération supportée par le _RA_. Les plus fréquents sont `timeout`et
`interval`. Vous trouverez la liste complète à l'adresse suivante:
<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/_resource_operations.html#idm47160757240816>

Concernant le timeout par exemple, ce dernier est de 20 secondes par défaut
pour toutes les opérations. Cette valeur par défaut peut être modifiée dans la
section `op_defaults` de la CIB, avec l'une ou l'autre de ces commandes:

~~~
crm_attribute --type op_defaults --name timeout --update 20s
pcs resource op defaults timeout=20s
~~~

Avec la commande `pcs` nous utilisons le mot clé `op <action>` pour définir
le paramétrage des différentes opérations. Le paramétrage pour ces actions
surcharge alors les valeurs par défaut. Voici un exemple:

~~~
# pcs resource create identifiant_resource type:fournisseur:nom \
    user=nom_user_resource                                      \
    meta migration-threshold=1                                  \
    op start timeout=60s
    op monitor timeout=10s interval=10s
~~~

__ATTENTION__: les valeurs par défaut exposées par les _RA_ sont des valeurs
__recommandées__. Elles ne sont pas appliquées automatiquement. Préciser les
timeouts de chaque action lors de la définition d'une ressource est recommandé
même s'ils sont identiques à la valeur par défaut. Cette pratique aide à la
compréhension rapide de la configuration d'un cluster.

Les _resource agent_ n'ont pas à se préoccuper des timeout de leurs actions.
Tout au plus, ces agents peuvent indiquer des timeout par défaut à titre de
recommandation seulement. Il reste à la charge de l'administrateur de définir
les différents timeout en tenant compte de cette recommandation.

Le daemon `execd`, qui exécute l'action, se charge d'interrompre une action dès
que son timeout est atteint. Habituellement, le cluster planifie alors des
actions palliatives à cette erreur (eg. _recovery_ ou _failover_).

:::

-----

### TP: création d'une ressource dans le cluster

::: notes

Création d'une première ressource "Dummy". Ce _resource agent_ existe
seulement à titre de démonstration et d'expérimentation.

1. afficher les détails de l'agent Dummy
2. créer le sous-répertoire `/opt/sub` sur les 3 nœuds.
3. créer une ressource `dummy1` utilisant le _RA_ Dummy

Il est possible de travailler sur un fichier XML offline en précisant
l'argument `-f /chemin/vers/xml` à la commande `pcs`. Utiliser un fichier
`dummy1.xml` pour créer la ressource et ses contraintes en une seule
transition.

* positionner le paramètre `state` à la valeur `/opt/sub/dummy1.state`
* vérifier son état toutes les 10 secondes
* positionner son attribut `migration-threshold` à `3`
* positionner son attribut `failure-timeout` à `4h`
* positionner un `stickiness` faible de `1`
* ajouter une forte préférence de `100` pour le nœud hanode1

Tout ce paramétrage doit être en surcharge des éventuelles valeurs par
défaut du cluster.

4. contrôler le contenu du fichier `dummy1.xml` et simuler son application
   avec `crm_simulate`
5. publier les modifications dans le cluster
6. consulter les logs du DC
7. observer les changements opérés

:::

-----

### Correction: création d'une ressource dans le cluster

::: notes


1. afficher les détails de l'agent Dummy

~~~console
# pcs resource describe ocf:pacemaker:Dummy
~~~

2. créer le sous-répertoire `/opt/sub` sur les 3 nœuds.

Sur chaque nœud:

~~~console
# mkdir -p /opt/sub
~~~

3. créer une ressource `dummy1` utilisant le _RA_ Dummy

~~~console
# pcs cluster cib dummy1.xml

# pcs -f dummy1.xml resource create dummy1 ocf:pacemaker:Dummy \
    state=/opt/sub/dummy1.state                                \
    op monitor interval=10s                                    \
    meta migration-threshold=3                                 \
    meta failure-timeout=4h                                    \
    meta resource-stickiness=1

# pcs -f dummy1.xml constraint location dummy1 prefers hanode1=100
~~~

4. contrôler le contenu du fichier `dummy1.xml` et simuler son application
avec `crm_simulate`

Contrôle de la syntaxe:

~~~console
# crm_verify -V --xml-file dummy1.xml
# pcs cluster verify -V dummy1.xml  # alternative avec pcs
~~~

Simuler ces modifications:

~~~
# crm_simulate --simulate --xml-file dummy1.xml

Current cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 dummy1	(ocf::pacemaker:Dummy):	Stopped

Transition Summary:
 * Start      dummy1     ( hanode1 )  

Executing cluster transition:
 * Resource action: dummy1          monitor on hanode3
 * Resource action: dummy1          monitor on hanode2
 * Resource action: dummy1          monitor on hanode1
 * Resource action: dummy1          start on hanode1
 * Resource action: dummy1          monitor=10000 on hanode1

Revised cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 dummy1	(ocf::pacemaker:Dummy):	Started hanode1
~~~

Nous observons dans cette sortie:

* l'état du cluster avant la transition (`Current cluster status`)
* les actions à réaliser (`Transition Summary` et `Executing cluster transition`)
* l'état attendu du cluster après transition (`Revised cluster status`)

5. publier les modifications dans le cluster

~~~
# pcs cluster cib-push dummy1.xml
~~~

6. consulter les logs du DC

Les log ont été remis en forme.

Actions prévues par `pengine`:

~~~
pengine:     info: RecurringOp:  Start recurring monitor (10s) for dummy1 on hanode1
pengine:     info: LogActions:   Leave   fence_vm_hanode1        (Started hanode2)
pengine:     info: LogActions:   Leave   fence_vm_hanode2        (Started hanode1)
pengine:     info: LogActions:   Leave   fence_vm_hanode3        (Started hanode1)
pengine:   notice: LogAction:  * Start      dummy1               (        hanode1)  
pengine:   notice: Calculated transition 21, saving in /.../pengine/pe-input-11.bz2
~~~

Actions initiées par `crmd`:

~~~
crmd:   info: Processing graph 21 derived from /var/.../pengine/pe-input-11.bz2
crmd: notice: Initiating monitor operation dummy1_monitor_0 on hanode3 | action 6
crmd: notice: Initiating monitor operation dummy1_monitor_0 on hanode2 | action 5
crmd: notice: Initiating monitor operation dummy1_monitor_0 locally on hanode1 | action 4
crmd:   info: Action dummy1_monitor_0 (5) confirmed on hanode2 (rc=7)
crmd:   info: Action dummy1_monitor_0 (6) confirmed on hanode3 (rc=7)
crmd:   info: Action dummy1_monitor_0 (4) confirmed on hanode1 (rc=7)
crmd: notice: Result of probe operation for dummy1 on hanode1: 7 (not running)

crmd: notice: Initiating start operation dummy1_start_0 locally on hanode1
lrmd:   info: executing - rsc:dummy1 action:start call_id:26
lrmd:   info: finished - rsc:dummy1 action:start call_id:26 exit-code:0
crmd: notice: Result of start operation for dummy1 on hanode1: 0 (ok)

crmd: notice: Initiating monitor operation dummy1_monitor_10000 locally on hanode1
lrmd:  debug: executing - rsc:dummy1 action:monitor call_id:27
~~~

Les actions `dummy1_monitor_0` vérifient que la ressource n'est démarrée pas
démarrée sur le nœud concerné. Ensuite, la ressource est démarrée sur
`hanode1` avec l'opération `dummy1_start_0`. Puis l'action de surveillance
`dummy1_monitor_10000` récurrente toutes les 10 secondes (`10000`ms) est
démarrée.

7. observer les changements

~~~console
# pcs status
# pcs config show
~~~

:::

-----

## Contraintes de colocation

* définit un lien entre plusieurs ressources
* la force du lien est définie par un score qui s'ajoute aux scores existant
* peut être un lien de colocalisation ou d'exclusion
  * Par exemple une VIP là où la ressource doit être démarrée
* attention à l'ordre de déclaration !

::: notes

Les contraintes de colocation servent à indiquer à Pacemaker où une ressource _A_ doit
être placée par rapport à une ressource _B_. Elles permettent de localiser deux ressources
au même endroit ou à des endroits différents (exclusion).

L'ordre des déclarations est important car cela implique que la ressource _A_ sera
assignée à un nœud après la ressource _B_. Cela implique que la contrainte de
localisation placée sur la ressource _B_ décide du placement de la ressource _A_.

Ces contraintes n'ont pas d'impact sur l'[ordre de démarrage][Contraintes d'ordre].

Dans le cas de PAF, il faut utiliser une contrainte de colocation pour que la VIP
soit montée sur le même nœud que le master.

[Explication](http://clusterlabs.org/doc/Colocation_Explained.pdf)

:::

-----

### TP: création des _RA_ (dummy2) dans le cluster


::: notes

1. ajouter une ressource `dummy2`

Utiliser un fichier `dummy2.xml` pour préparer les actions.

* positionner le paramètre `state` à la valeur `/opt/sub/dummy2.state`
* vérifier son état toutes les 10 secondes
* positionner son attribut `migration-threshold` à `3`
* positionner son attribut `failure-timeout` à `4h`
* positionner un `stickiness` élevé de `100`
* interdire la ressource de démarrer sur le même nœud que `dummy1`
* ajouter une faible préférence de `10` pour le nœud hanode2

Note : il est important d'utiliser un fichier xml pour appliquer les contraintes de localisation avant de démarrer la
ressource

4. contrôler le contenu du fichier `dummy2.xml` et simuler son application
5. publier les modifications dans le cluster
6. observer les changements

:::

-----

### Correction: création des _RA_ (dummy2) dans le cluster

::: notes


1. ajouter une ressource `dummy2`

~~~console
# pcs cluster cib dummy2.xml

# pcs -f dummy2.xml resource create dummy2 ocf:pacemaker:Dummy \
    state=/opt/sub/dummy2.state                                \
    op monitor interval=10s                                    \
    meta migration-threshold=3                                 \
    meta failure-timeout=4h                                    \
    meta resource-stickiness=100

# pcs -f dummy2.xml constraint location dummy2 prefers hanode2=10

# pcs -f dummy2.xml constraint colocation add dummy2 with dummy1 -INFINITY
~~~

4. contrôler le contenu du fichier `dummy2.xml` et simuler son application

~~~console
# pcs cluster verify -V dummy2.xml
# crm_simulate -S -x dummy2.xml

Current cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 dummy1	(ocf::pacemaker:Dummy):	Started hanode1
 dummy2	(ocf::pacemaker:Dummy):	Stopped

Transition Summary:
 * Start      dummy2     ( hanode3 )  

Executing cluster transition:
 * Resource action: dummy2          monitor on hanode3
 * Resource action: dummy2          monitor on hanode2
 * Resource action: dummy2          monitor on hanode1
 * Resource action: dummy2          start on hanode3
 * Resource action: dummy2          monitor=10000 on hanode3

Revised cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 dummy1	(ocf::pacemaker:Dummy):	Started hanode1
 dummy2	(ocf::pacemaker:Dummy):	Started hanode3
~~~

Ici, `pengine` a prévu de démarrer `dummy2` sur `hanode3`.

5. publier les modifications dans le cluster

~~~console
# pcs cluster cib-push dummy2.xml
~~~

6. observer les changements opérés

~~~console
# crm_mon -Dn
# pcs status
# pcs config show
~~~

:::

-----

## Contraintes d'ordre

* concerne des ressources liées
* déclaration de l'ordre de déclenchement des actions
  * `stop`
  * `start`
  * `promote`
  * `demote`
* ordre obligatoire, optionnel ou sérialisé
* symétrique ou asymétrique

::: notes

Ce type de contrainte peut être nécessaire pour spécifier l'ordre de
déclenchement des actions. Par exemple, le déplacement d'une IP virtuelle une
fois que le service a été déplacé sur un autre nœud.

Il existe trois type différents, précisé par l'attribut `kind` :

* `Mandatory`: la seconde action n'est pas exécutée tant que la première
  action n'a pas réussi
* `Optional`: les deux actions peuvent être exécutées indépendamment, mais
respecterons l'ordre imposé si elles doivent l'être dans la même transition
* `Serialize`: les actions ne doivent pas être exécutées en même temps par
  le cluster. L'ordre importe peu ici.

Si une contrainte d'ordre est symétrique (attribut `symmetrical`), elle
s'applique aussi pour les actions opposées, mais dans l'ordre inverse.

:::


-----

### TP: Contrainte d'ordre

::: notes

Il est recommandé de conserver un terminal avec un `crm_mon` actif tout au long
de ce TP.

1. créer une contrainte d'ordre non symétrique qui force le démarrage de
`dummy1` avant celui de `dummy2`
2. arrêter la ressource `dummy1` et observer l'influence sur `dummy2`
3. arrêter la ressource `dummy2`, puis démarrer `dummy2`
4. démarrer `dummy1`
5. vérifiez dans les log __du DC__ l'ordre des actions

:::

-----

### Correction: Contrainte d'ordre

::: notes

Il est recommandé de conserver un terminal avec un `crm_mon` actif tout au long
de ce TP.

1. créer une contrainte d'ordre non symétrique qui force le démarrage de
   `dummy1` avant celui de `dummy2`

~~~console
# pcs constraint order start dummy1 then start dummy2 symmetrical=false kind=Mandatory
Adding dummy1 dummy2 (kind: Mandatory) (Options: first-action=start then-action=start symmetrical=false)
~~~

2. arrêter la ressource `dummy1` et observer l'influence sur `dummy2`

~~~console
# pcs resource disable dummy1
~~~

La ressource `dummy2` ne s'arrête pas. La contrainte ne concerne que le
démarrage des deux ressources.

3. arrêter la ressource `dummy2`, puis démarrer `dummy2`

~~~console
# pcs resource disable --wait dummy2
# pcs resource enable dummy2
~~~

La ressource `dummy2` ne démarre pas. Cette dernière ne peut démarrer
qu'après le démarrage de `dummy1`, mais cette dernière est arrêtée.

4. démarrer `dummy1`

~~~console
# pcs resource enable dummy1
~~~

Les deux ressources démarrent.

5. vérifiez dans les log __du DC__ l'ordre des actions

Les log ont été remis en forme.

~~~console
# grep 'dummy._start.*confirmed' /var/log/cluster/corosync.log
crmd:  info:  Action dummy1_start_0 (48) confirmed on hanode1 (rc=0)
crmd:  info:  Action dummy2_start_0 (50) confirmed on hanode3 (rc=0)
~~~

L'ordre des action est précisé par leur ID, ici 48 et 50. Il est possible
d'aller plus loin avec `crm_simulate` et ses options `-S`, `-G` et `-x` en
indiquant la transition produite par `pengine` dans le répertoire
`/var/lib/pacemaker/pengine`. Cette commande et analyse est laissée à
l'exercice du lecteur.

:::


-----

## Regroupement de ressources

* "group" : regroupement de ressources liées ("primitives")
* simplification de déclaration de contraintes de "colocation"
* sont démarrées dans l'ordre de déclaration
* sont arrêtées dans l'ordre inverse de déclaration
* une impossibilité de démarrer une ressource affecte les ressources
  suivantes dans le groupe

::: notes

La notion de groupe est un raccourcis syntaxique qui permet de simplifier les
déclarations en regroupant les contraintes d'un ensemble de ressources.

Les attributs d'un groupe permettent notamment de définir la priorité et le
rôle du group ou encore de mettre l'ensemble du groupe en maintenance.

La `stickiness` d'un groupe correspond à la somme des `stickiness` des ressources
présentes dans ce groupe.

Dans le cas de PAF, on utilise un groupe pour rassembler la ressource PostgreSQL
master et la VIP.

:::

-----

### TP: groupe de ressource

::: notes

1. créer une ressource `dummy3`

Utiliser un fichier `dummy3.xml` pour préparer les actions.

* positionner le paramètre `state` à la valeur `/opt/sub/dummy3.state`
* vérifier son état toutes les 10 secondes
* positionner son attribut `migration-threshold` à `3`
* positionner son attribut `failure-timeout` à `4h`
* positionner un `stickiness` élevé de `100`

2. créer un group `dummygroup` qui regroupe les ressources `dummy3` et
   `dummy2` dans cet ordre
3. créer une contrainte d'ordre qui impose de démarrer `dummy1` avant `dummy3`
4. créer une contrainte d'exclusion entre `dummygroup` et `dummy1` d'un score
   de `-1000`
5. appliquer les modifications au cluster
6. désactiver les ressources `dummy1`, `dummy2` et `dummy3`, puis les
   réactiver en même temps
7. observer l'ordre choisi par pengine pour le démarrage de l'ensemble des ressources

:::

-----

### Correction: groupe de ressource

::: notes

1. créer une ressource `dummy3`

~~~console
# pcs cluster cib dummy3.xml

# pcs -f dummy3.xml resource create dummy3 ocf:pacemaker:Dummy \
    state=/opt/sub/dummy3.state                                \
    op monitor interval=10s                                    \
    meta migration-threshold=3                                 \
    meta failure-timeout=4h                                    \
    meta resource-stickiness=100
~~~

2. créer un group `dummygroup` qui regroupe les ressources `dummy3` et `dummy2` dans cet ordre

~~~console
# pcs -f dummy3.xml resource group add dummygroup dummy3 dummy2
~~~

3. créer une contrainte d'ordre qui impose de démarrer `dummy1` avant `dummy3`

~~~console
# pcs -f dummy3.xml constraint order start dummy1 then start dummy3 symmetrical=false kind=Mandatory
Adding dummy1 dummy3 (kind: Mandatory) (Options: first-action=start then-action=start symmetrical=false)
~~~

4. créer une contrainte d'exclusion entre `dummygroup` et `dummy1` d'un score
   de `-1000`

~~~console
# pcs -f dummy3.xml constraint colocation add dummygroup with dummy1 -1000
~~~

5. appliquer les modifications au cluster

~~~console
# pcs cluster verify -V dummy3.xml
# crm_simulate -S -x dummy3.xml

# pcs cluster cib-push dummy3.xml
CIB updated
~~~

6. désactiver les ressources `dummy1`, `dummy2` et `dummy3`, puis les
   réactiver en même temps

~~~
# pcs resource disable --wait dummy1 dummy2 dummy3
# pcs resource enable dummy1 dummy2 dummy3
~~~

7. observer l'ordre choisi par pengine pour le démarrage de l'ensemble des ressources

Les ressources sont démarrés dans l'ordre suivant: `dummy1`, `dummy3` puis
`dummy2`. Les log ont été remis en forme.

~~~
# grep 'dummy._start.*confirmed' /var/log/cluster/corosync.log
crmd:  info: Action dummy1_start_0 (10) confirmed on hanode1 (rc=0)
crmd:  info: Action dummy3_start_0 (12) confirmed on hanode3 (rc=0)
crmd:  info: Action dummy2_start_0 (14) confirmed on hanode3 (rc=0)
~~~

:::

-----

### TP: failcounts

::: notes

Nous provoquons dans ce TP une défaillance pour travailler dessus.

1. renommer `/opt/sub` en `/opt/sub2` sur le nœud hébergeant `dummy1`

Attendre que le cluster réagisse à la défaillance.

2. observer le failcount de `dummy1` avec `crm_failcount` ou `pcs`
3. chercher dans les log les causes de cette valeur
4. réparer le problème sur `hanode1` et réinitialiser le failcount avec `pcs`
5. expliquer le comportement de `dummy1`

Conseil: observer les scores.

:::

-----

### Correction: failcounts

::: notes

1. renommer `/opt/sub` en `/opt/sub2` sur le nœud hébergeant `dummy1`

Observer le cluster et ses réactions dans un terminal à l'aide de `crm_mon`:

~~~console
# crm_mon -Dnf
~~~

Renommer le répertoire pour provoquer une défaillance:

~~~console
# mv /opt/sub /opt/sub2
~~~

Attendre que le cluster réagisse à la défaillance.

2. observer le failcount de `dummy1` avec `crm_failcount` ou `pcs`

~~~console
# crm_failcount -r dummy1 -N hanode1 -G
scope=status  name=fail-count-dummy1 value=INFINITY

# crm_failcount -r dummy1 -N hanode3 -G
scope=status  name=fail-count-dummy1 value=0

# pcs resource failcount show dummy1
Failcounts for dummy1
hanode1: INFINITY
~~~

3. chercher dans les log les causes de cette valeur

Rechercher dans les log du DC les mots clé `failcount` et `dummy1` pour
identifier les messages relatifs à cette activité. Ci-après une explication
des log remis en forme.

Détection de l'erreur lors d'une opération `monitor` et incrément du
failcount pour la ressource sur le nœud où elle se situe:

~~~
crmd:  info: Updating failcount for dummy1 on hanode1 after failed monitor: rc=7 (update=value++)
attrd: info: Expanded fail-count-dummy1#monitor_10000=value++ to 1
attrd: info: Setting fail-count-dummy1#monitor_10000[hanode1]: (null) -> 1
~~~

Calcul d'une transition afin de rétablir un état stable du cluster. Le
sous-processus `pengine` prévoit de redémarrer `dummy1` sur son nœud courant:

~~~
pengine:   info:   Start recurring monitor (10s) for dummy1 on hanode1
pengine: notice: * Recover  dummy1  (        hanode1)  
pengine:   info:   Leave    dummy3  (Started hanode2)
pengine:   info:   Leave    dummy2  (Started hanode2)
~~~

Ce choix dépend de la propriété `on-fail` de l'opération, à `restart` par
défaut. Pour plus de détail, voir:
<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Pacemaker_Explained/_resource_operations.html#s-operation-properties>

L'action `recovery` consiste a arrêter et démarrer la ressource concernée.
Une fois l'opération `stop` réalisée, nous observons que le `start` échoue. 

~~~
crmd:  notice: te_rsc_command:    Initiating stop operation dummy1_stop_0 on hanode1
crmd:    info: match_graph_event: Action dummy1_stop_0 (6) confirmed on hanode1 (rc=0)
crmd:  notice: te_rsc_command:    Initiating start operation dummy1_start_0 on hanode1
crmd: warning: status_from_rc:    Action 14 (dummy1_start_0) on hanode1 failed (target: 0 vs. rc: 1): Error
crmd:  notice: abort_transition_graph:    Transition aborted by operation dummy1_start_0 'modify' on hanode1: Event failed
crmd:    info: update_failcount:  Updating failcount for dummy1 on hanode1 after failed start: rc=1 (update=INFINITY)
attrd:   info: attrd_peer_update: Setting fail-count-dummy1#start_0[hanode1]: (null) -> INFINITY 
~~~

Si une opération `start` échoue, la décision du cluster dépend de deux
paramètres: `on-fail` que nous avons vu précédemment et  le paramètre du
cluster `start-failure-is-fatal`, positionné à `true` par défaut.

Ici, l'opération `start` ayant échoué, le cluster décide donc de
positionner un failcount à INFINITY à cause de `start-failure-is-fatal`.

La ressource `dummy1` ayant un failcount infini sur `hanode1`, `pengine`
décide de déplacer la ressource sur `hanode3`:

~~~
pengine:   info:   Start recurring monitor (10s) for dummy1 on hanode3
pengine: notice: * Recover dummy1  (hanode1 -> hanode3)
pengine:   info:   Leave   dummy3  (Started hanode2)
pengine:   info:   Leave   dummy2  (Started hanode2)
~~~

Les opérations sont réalisées sans erreurs:

~~~
crmd:  debug: Unpacked transition 22: 3 actions in 3 synapses
[...]
crmd: notice: Initiating stop operation dummy1_stop_0 on hanode1
crmd:   info: Action dummy1_stop_0 confirmed on hanode1 (rc=0)
[...]
crmd: notice: Initiating start operation dummy1_start_0 on hanode3
crmd:   info: Action dummy1_start_0 confirmed on hanode3 (rc=0)
[...]
crmd: notice: Initiating monitor operation dummy1_monitor_10000 on hanode3
crmd:   info: Action dummy1_monitor_10000 confirmed on hanode3 (rc=0)
[...]
crmd:  debug: Transition 22 is now complete
~~~

4. réparer le problème sur `hanode1` et réinitialiser le failcount avec `pcs`

~~~console
# mv /opt/sub2 /opt/sub
# pcs resource failcount reset dummy1 hanode1
~~~

5. expliquer le comportement de `dummy1`

La ressource `dummy1` retourne sur le nœud `hanode1` dès que nous y
supprimons son ancien failcount.

Effectivement, `dummy1` a été créé avec un `stickiness` à `1` et une
contrainte de location sur `hanode1` de `100`.

~~~
# pcs constraint location show dummy1
Location Constraints:
  Resource: dummy1
    Enabled on: hanode1 (score:100)
[...]

# pcs resource show dummy1
 Resource: dummy1 (class=ocf provider=pacemaker type=Dummy)
  Attributes: state=/opt/sub/dummy1.state
  Meta Attrs: failure-timeout=4h migration-threshold=3 resource-stickiness=1
[...]
~~~

Avant de retirer son failcount sur `hanode1`, ses scores étaient les suivants:

~~~
native_color: dummy1 allocation score on hanode1: -INFINITY
native_color: dummy1 allocation score on hanode2: -220
native_color: dummy1 allocation score on hanode3: 1
~~~

Sur `hanode1`, `dummy1` cumulait le score de location de `100` et le failcount de
`-INFINITY`, soit un total de `-INFINITY`. Le score de `1` correspondant au
stickiness sur `hanode3`.

Après la suppression du failcount de -INFINITY, les scores sont donc devenus:

* `100` pour `dummy1` sur `hanode1` (score de location)
* `1` pour `dummy1` sur `hanode3` (score de stickiness)

Par conséquent `pengine` décide de déplacer `dummy1` sur le nœud où il a
le plus gros score: `hanode1`. Après migration, les scores deviennent alors:

~~~
native_color: dummy1 allocation score on hanode1: 101
native_color: dummy1 allocation score on hanode2: -220
native_color: dummy1 allocation score on hanode3: 0
~~~

:::

-----

## Édition des ressources

* la modification d'un paramètre provoque une réaction du cluster
* soit le redémarrage de la ressource
* soit son rechargement à chaud
* dépend de la ressource et du paramètre

::: notes

La configuration des ressources peut être faite avec `pcs resource update` ou
avec l'outil `crm_resource` et l'option `-s / --set-parameter` ou `-d /
--delete-parameter`.

On distingue les paramètres de :

* configuration propre à la ressource, les paramètres propres à chaque RA
* configuration du RA, les paramètres communs à tous les RA (modifiable avec l'option --meta)
* configuration des opérations.

Un paramètre propre à la ressource est modifiable à chaud si:

* l'agent supporte l'action `reload`
* ce paramètre n'est pas marqué comme étant `unique`

:::

-----

### TP: modification paramètre avec reload ou restart

::: notes

1. afficher la description du RA `ocf:pacemaker:Dummy`
2. identifier dans la description le paramètre `fake`
3. afficher la valeur actuelle du paramètre `fake`
4. modifier la valeur de `fake` avec `test`
5. vérifier le comportement dans les traces

Notes: utilisez `crm_resource` ou `pcs resource`

:::

-----

### Correction: modification paramètre avec reload ou restart

::: notes

1. afficher la description du RA `ocf:pacemaker:Dummy`

~~~console
# pcs resource describe ocf:pacemaker:Dummy
~~~

2. identifier dans la description le paramètre `fake`

~~~
[...]
  fake: Fake attribute that can be changed to cause a reload
[...]
~~~

3. afficher la valeur actuelle du paramètre `fake`

~~~console
# crm_resource -r dummy1 -g fake
Attribute 'fake' not found for 'dummy1'
~~~

4. modifier la valeur de `fake` avec `test`

~~~console
# crm_resource -r dummy1 -p fake -v test
~~~

ou

~~~console
# pcs resource update dummy1 fake=test
~~~

5. vérifier le comportement dans les traces

Log du DC remis en forme:

~~~
pengine:   info: Start recurring monitor (10s) for dummy1 on hanode1
pengine: notice: * Reload  dummy1  (hanode1)
[...]
crmd:     debug: Unpacked transition 34: 2 actions in 2 synapses
[...]
crmd:    notice: Initiating reload operation dummy1_reload_0 on hanode1
crmd:      info: Action dummy1_start_0  confirmed on hanode1
[...]
crmd:    notice: Initiating monitor operation dummy1_monitor_10000 on hanode1
crmd:      info: Action dummy1_monitor_10000 confirmed on hanode1
[...]
crmd:    notice: Transition 34 (Complete=2): Complete
~~~

Log de `hanode1`:

~~~
crmd:    debug: Cancelling op 55 for dummy1
lrmd:     info: Cancelling ocf operation dummy1_monitor_10000
lrmd:    debug: finished - rsc:dummy1 action:monitor call_id:55  exit-code:0
crmd:    debug: Op 55 for dummy1 (dummy1:55): cancelled
[...]
crmd:     info: Performing key=7:34:0:cc37b9f1-860c-4a1f-bbac-db48f7cd080a op=dummy1_reload_0
lrmd:     info: executing - rsc:dummy1 action:reload call_id:57
lrmd:     info: finished - rsc:dummy1 action:reload call_id:57 pid:13714 exit-code:0 exec-time:69ms queue-time:0ms
crmd:   notice: Result of reload operation for dummy1 on hanode1: 0 (ok)
[...]
crmd:     info: Performing key=3:34:0:cc37b9f1-860c-4a1f-bbac-db48f7cd080a op=dummy1_monitor_10000
lrmd:    debug: executing - rsc:dummy1 action:monitor call_id:58
lrmd:    debug: finished - rsc:dummy1 action:monitor call_id:58 pid:13722 exit-code:0 exec-time:30ms queue-time
crmd:     info: Result of monitor operation for dummy1 on hanode1: 0 (ok)
~~~

:::


-----

## Ressources _Multi-State_

* les ressource multi-state sont des clones avec des rôles différents
* nécessite de configurer un `monitor` distinct par rôle
* une ressource supplémentaire dédiée à la gestion des clones et leurs rôles
* nombre de clones modifiable
* les clones démarrent toujours d'abord en `Slave`
* les master score permettent de désigner le ou les clones à promouvoir

::: notes

Comme expliqué dans le chapitre [_Ressource Agent_ (_RA_)] il existe
plusieurs type de ressources, dont les ressources clones ou les ressources
_multi-state_. Ces derniers héritent de toutes les propriétés des ressources
clones et ajoute une notion supplémentaire de rôle primaire et secondaire
appelés respectivement `Master` et `Slave`.

Une ressource _multi-state_ se crée en deux étapes:

* création d'une ressource type utilisant le RA voulu
* création d'une ressource _multi-state_ qui administre la ressource précédemment
  créée, la clone en fonction de sa configuration et gère les rôles parmi
  ces clones.

Particularité des ressources géré en _muti-state_, ces dernières doivent
comporter une opération `monitor` différente pour les rôles `Slave` et
`Master`, chacune avec une récurrence différente. Ce dernier point est lié à un
détail d'implémentation de Pacemaker qui identifie les opérations par un
identifiant composé: du nom de la ressource, de l'opération, de sa récurrence.
Ainsi, `pgsqld_monitor_15000` désigne l'opération `monitor` sur la ressource
`pgsqld` exécutée toute les 15 secondes. Voir:

<https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/1.1/html/Pacemaker_Explained/_monitoring_multi_state_resources.html>

Les différents paramètres utiles à une ressource _multi-state_ sont définis dans
la documentation de Pacemaker à ces pages:

* liés aux clones: <https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/1.1/html/Pacemaker_Explained/_clone_options.html>
* liés aux _multi-state_: <https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/1.1/html/Pacemaker_Explained/_multi_state_options.html>

Les paramètres intéressants dans le cadre de cette formation sont:

* `clone-max`: nombre de clones dans tous le cluster, par défaut le nombre de
  nœud du cluster
* `clone-node-max`: nombre de clone maximum sur chaque nœud, par défaut à `1`
* `master-max`: nombre maximum de clone promu au sein du cluster, par défaut
  à `1`
* `master-node-max`: nombre maximum de clone promu sur chaque nœud, par
  défaut à `1`
* `notify`: activer les opérations `notify` si le RA le supporte, par défaut
  à `false`

Nous constatons que la plupart des valeurs par défaut sont correcte pour PAF.
Seule le paramètre `notify` doit être __obligatoire__ activé dans le cadre
de PAF.

Enfin, tous les clones d'une ressource multi-state sont __toujours__ démarrés
avec le rôle `Slave`. Ensuite, les clones avec les _master scores_ les plus
élevés sont sélectionnés pour être promus en `Master` (voir aussi à ce propos
[Attributs de nœuds particuliers] ).

![Diagramme démarrage ressource multi-state](medias/paf-ms-roles.png)

Ces master scores sont positionnés le plus souvent par le RA, mais peuvent
aussi être manipulés par l'administrateur si besoin.

:::

-----

::: notes

### TP: création d'une ressource _multi-state_

Utiliser un fichier `dummy-ms.xml` pour effectuer vos modifications.

1. créer une ressource `Dummyd` avec le RA `ocf:pacemaker:Stateful`

* surveiller le rôle `Master` toutes les 5 secondes
* surveiller le rôle `slave` toutes les 6 secondes

2. créer la ressource multi-state `Dummyd-clone` clonant `Dummyd`

* activer les notifications
* dix clones autorisés
* deux rôles `Master` autorisés

3. appliquer vos modifications sur le cluster
4. expliquer le nombre de clone de `Dummyd` démarrés
5. observer combien de clones ont été promus en `Master`

:::

-----

### Correction: création d'une ressource _multi-state_

::: notes

Utiliser un fichier `dummy-ms.xml` pour effectuer vos modifications.

~~~console
# pcs cluster cib dummy-ms.xml
~~~

1. créer une ressource `Dummyd` avec le RA `ocf:pacemaker:Stateful`

~~~console
# pcs -f dummy-ms.xml resource create Dummyd ocf:pacemaker:Stateful \
    op monitor interval=5s role="Master"                            \
    op monitor interval=6s role="Slave"
~~~

2. créer la ressource multi-state `Dummyd-clone` clonant `Dummyd`

* activer les notifications
* dix clones autorisés
* deux rôles `Master` autorisés

Ou, en tenant compte des valeurs par défaut:

~~~console
# pcs -f dummy-ms.xml resource master Dummyd-clone Dummyd \
    notify=true clone-max=10 master-max=2
~~~

3. appliquer vos modifications sur le cluster

~~~console
# pcs cluster verify -V dummy-ms.xml
# crm_simulate -S -x dummy-ms.xml
# pcs cluster cib-push dummy-ms.xml
~~~

4. expliquer le nombre de clone de `Dummyd` démarrés

Trois clones ont été démarrés dans le cluster. Malgré la valeur de
`clone-max=10`, le paramètre `clone-node-max` par défaut à `1` empêche d'en
démarrer plus d'un par nœud.

~~~
pengine: debug: Allocating up to 10 Dummyd-clone instances to a possible 3 nodes (at most 1 per host, 3 optimal)
pengine: debug: Assigning hanode3 to Dummyd:0
pengine: debug: Assigning hanode2 to Dummyd:1
pengine: debug: Assigning hanode1 to Dummyd:2
pengine: debug: All nodes for resource Dummyd:3 are unavailable, unclean or shutting down
pengine: debug: Could not allocate a node for Dummyd:3
pengine:  info: Resource Dummyd:3 cannot run anywhere
[...]
pengine: debug: All nodes for resource Dummyd:9 are unavailable, unclean or shutting down
pengine: debug: Could not allocate a node for Dummyd:9
pengine:  info: Resource Dummyd:9 cannot run anywhere
pengine: debug: Allocated 3 Dummyd-clone instances of a possible 10
~~~

5. observer combien de clones ont été promus en `Master`

Deux clones ont été promus.

Lors du démarrage des instances `Dummyd`, l'agent positionne le master score
de sa ressource à `5`. Voir la fonction `stateful_start` dans le code source
de l'agent à l'emplacement `/usr/lib/ocf/resource.d/pacemaker/Stateful`.

Le paramètre `master-max` étant positionné à `2`, le cluster choisi deux
clones à promouvoir parmis les trois disponibles.

:::

-----

## Suppression des ressources

* `pcs resource delete` supprime une ressource ou un groupe
* deux étapes :
  * stopper la ressource
  * supprimer la ressource

::: notes

La supression de ressource peut être réalisée par `pcs resource delete
<resource_name>`.

La supression d'un groupe supprime non seulement ce groupe mais aussi les
ressources qu'il contient.

:::

-----

### TP: supprimer les dummy

::: notes

1. lister les ressources du cluster
2. supprimer les ressources `dummy1` et `dummy2`
3. afficher l'état du cluster
4. supprimer le groupe `dummygroup`
5. afficher l'état du cluster
6. supprimer la ressource `Dummyd-clone`
7. afficher l'état du cluster

:::

-----

### Correction: supprimer les dummy

::: notes

1. lister les ressources du cluster

~~~console
# pcs resource show
 Master/Slave Set: Dummyd-clone [Dummyd]
     Masters: [ hanode1 hanode2 ]
     Slaves: [ hanode3 ]
 dummy1	(ocf::pacemaker:Dummy):	Started hanode1
 Resource Group: dummygroup
     dummy3	(ocf::pacemaker:Dummy):	Started hanode2
     dummy2	(ocf::pacemaker:Dummy):	Started hanode2


~~~

2. supprimer les ressources `dummy1` et `dummy2`

~~~console
# pcs resource delete dummy1
Attempting to stop: dummy1... Stopped
# pcs resource delete dummy2
Attempting to stop: dummy2... Stopped
~~~

3. afficher l'état du cluster

~~~console
# pcs resource show
 Master/Slave Set: Dummyd-clone [Dummyd]
     Masters: [ hanode1 hanode2 ]
     Slaves: [ hanode3 ]
 Resource Group: dummygroup
     dummy3	(ocf::pacemaker:Dummy):	Started hanode2

~~~

4. supprimer le groupe dummygroup

~~~console
# pcs resource delete dummygroup
Removing group: dummygroup (and all resources within group)
Stopping all resources in group: dummygroup...
Deleting Resource (and group) - dummy3
~~~

5. afficher l'état du cluster

~~~console
# pcs resource show
 Master/Slave Set: Dummyd-clone [Dummyd]
     Masters: [ hanode1 hanode2 ]
     Slaves: [ hanode3 ]
~~~

6. supprimer la ressource `Dummyd-clone`

~~~console
# pcs resource delete Dummyd-clone
Attempting to stop: Dummyd... Stopped
~~~

7. afficher l'état du cluster

~~~console
# pcs resource show
NO resources configured
~~~

:::

-----

## Règles

* possibilité de modifier les contraintes selon des conditions
  * par exemple une plage horaire

::: notes

Les règles permettent de définir :

* les contraintes de localisation ,
* les options et attributs d'instance d'une ressource ,
* les options du cluster ,

en fonction :

* des attributs d'un nœud ,
* de l'heure, de la date ou de la périodicité  (à la manière d'une crontab) ,
* d'une durée.

Pacemaker recalcule l'état du cluster sur la base d'évènements. Il est possible
qu'aucun évènement ne se produise pendant une période, ce qui empêcherait le
déclenchement d'une modification de configuration lié à une règle temporelle.
Il faut donc configurer le paramètre `cluster-recheck-interval` a une valeur adaptée
pour s'assurer que les règles basées sur le temps soient exécutées.

Les versions récentes de Pacemaker (à partir de la version 2.0.3) sont plus
fines à ce propos. Le `cluster-recheck-interval` est calculé dynamiquement en
fonction des contraintes, règles et différents timeout existants, à une
exception près. Voir à ce propos:
<https://lists.clusterlabs.org/pipermail/users/2019-September/026360.html>

Les règles peuvent être utilisées pour favoriser l'utilisation d'un nœud plus
puissant en fonction de la périodes de la journée ou du nombre de CPU.

Il faut cependant garder à l'esprit que la bascule d'une ressource PostgreSQL n'est
pas transparente et que la [simplicité][KISS] doit rester de mise.

:::


-----

# PAF

Configuration et Mécanique de PAF

-----

## Historique PAF

* agent officiel `pgsql` fastidieux et vieillissant
* premier agent stateless `pgsql-resource-agent`
* PAF est la seconde génération en mode stateful
* développé en bash, puis porté en perl

::: notes

Il existe déjà un agent `pgsql` distribué par le projet `resource-agents`.
Cependant, cet agent accumule plusieurs défauts:

* très fastidieux à mettre en œuvre
* plusieurs objectifs: supporte les architectures _shared disk_ ou _shared nothing_
* difficile à maintenir: code complexe, en bash
* procédures lourdes: pas de switchover, procédures lourdes, fichier de lock, etc
* configuration complexe: 31 paramètres disponibles
* détails d'implémentation visibles dans le paramétrage
* ne supporte pas le `demote` officieusement

Pour les besoins d'un projet où cet agent était peu adapté à l'environnement,
un premier agent stateless nommé `pgsqlsr` a été développé. C'est le projet
`pgsql-resource-agent`, toujours disponible aujourd'hui mais plus maintenu. Ce
projet avait l'avantage d'être très simple. Cependant, il imposait des limites
importantes: un seul secondaire possible, un seul failover automatique
autorisé, pas de switchover.

Suite à cette expérience, les auteurs ont créés le projet PAF, un nouvel agent
_multi-state_ exploitant au maximum les fonctionnalités de Pacemaker. Il a d'abord
été développé en bash, puis porté en perl, langage plus bas niveau, plus
lisible, plus efficace, plus fonctionnel.

:::

-----

## Limitations

* version de PostgreSQL supportée 9.3+
* le demote de l'instance primaire nécessite un arrêt
* trop strict sur l'arrêt brutal d'une instance
* pas de reconstruction automatique de l'ancien primaire après failover
* pas de gestion des slots de réplication

::: notes

Une incohérence entre l'état de l'instance et le controldata provoque une
erreur fatale ! Ne __jamais__ utiliser `pg_ctl -m immediate stop` !

Limitations levées:

* ne gère pas plusieurs instances PostgreSQL sur un seul nœud. Corrigé dans le commit 1a7d375.
* n'exclut pas une instance secondaire quel que soit son retard. Ajout du parametre maxlag dans le commit a3bbfa3.

Fonctionnalités manquantes dans PostgreSQL pour améliorer la situation:

* valider sur l'esclave ce qu'il a reçu du maître (cas du switchover)
* demote «à chaud»

:::

-----

## Installation PAF

* disponible directement depuis les dépôts PGDG RPM ou DEB
* paquets disponibles depuis github
* possibilité de l'installer à la main

::: notes

PAF peut être installé manuellement ou via les paquets mis à disposition sur
les dépôts communautaires PGDG ou encore ceux de Debian.

Les paquets sont aussi mis à disposition depuis le dépôt github du projet:
<https://github.com/ClusterLabs/PAF/releases/latest>

:::

-----

### TP: installation de PAF

::: notes

1. installer le dépôt PGDG pour CentOS 7 sur tous les nœuds
2. installer PostgreSQL 12 sur sur tous les nœuds
3. chercher puis installer le paquet de PAF sur tous les nœuds

:::

-----

### Correction: installation de PAF

::: notes

1. installer le dépôt PGDG pour CentOS 7 sur tous les nœuds

~~~console
# yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
~~~

2. installer PostgreSQL 12 sur sur tous les nœuds

~~~console
# yum install -y postgresql12 postgresql12-contrib postgresql12-server
~~~

3. chercher puis installer le paquet de PAF sur tous les nœuds

~~~console
# yum search paf
Loaded plugins: fastestmirror
Loading mirror speeds from cached hostfile
 * base: centos.mirrors.proxad.net
 * extras: centos.mirror.fr.planethoster.net
 * updates: centos.crazyfrogs.org
=============================== N/S matched: paf ===============================
resource-agents-paf.noarch : PostgreSQL resource agent for Pacemaker

  Name and summary matches only, use "search all" for everything.

# yum install -y resource-agents-paf
~~~

:::

-----

## Pré-requis de PAF

* supporte PostgreSQL à partir de la version 9.3 et supérieure
* _hot standby_ actif: doit pouvoir se connecter aux secondaires
* réplication streaming active entre les nœuds
  * nécessite:
    * `application_name` égal au nom du nœud
    * `recovery_target_timeline = 'latest'`
  * configurée dans :
    * pg11 et avant : modèle de fichier de configuration `recovery.conf.pcmk`
    * pg12 et après : fichier de configuration de PostgreSQL
* le cluster PostgreSQL doit être prêt avant le premier démarrage
* PostgreSQL doit être désactivé au démarrage du serveur
* empêcher le _wal receiver_ de se connecter sur sa propre instance
  * eg. ajout d'une règle `reject` dans `pg_hba.conf`

::: notes

L'agent PAF a peu de pré-requis.

Il supporte toutes les version de PostgreSQL supérieure ou égale à la version
9.3.

Le `recovery.conf` a disparu avec la version 12 de PostgreSQL, les paramètres
qu'il contenait sont désormais renseignés dans le fichier de configuration de
l'instance.

Le contrôleur du cluster à besoin de connaître le statut de chaque instance:
primaire ou secondaire. Ainsi, l'action `monitor` est exécutée à intervalle
régulier autant sur le primaire que sur les secondaires. Il est donc essentiel
que le paramètre `hot standby` soit activé sur toutes les instances, même sur
un primaire qui démarre toujours en secondaire d'abord ou qui peut être
repositionné en secondaire sur décision du cluster ou sur commande.

Au tout premier démarrage du cluster, PAF recherche parmi les instances
configurées quel est l'instance principale. Il est donc essentiel d'avoir créé
le cluster PostgreSQL avant la création de la ressource dans Pacemaker et
que ce dernier soit fonctionnel dès son démarrage.

Afin de permettre à PAF de faire le lien entre des connexions de réplication
et le nom des nœuds du cluster, il faut donner le nom du nœud où se trouve
l'instance dans la chaine de connexion (`primary_conninfo`) en utilisant le
paramètre `application_name`.

Lors de la création de la ressource, Pacemaker s'attend à la trouver éteinte.
Il n'est pas vital que les instances soient éteintes, mais cela reste
préférable afin d'éviter une légère perte de temps et des erreurs inutiles
dans les log et les événements du cluster.

Étant donné que Pacemaker contrôle entièrement le cluster PostgreSQL, ce
dernier doit être désactivé au démarrage du serveur.

Il est recommandé d'empêcher activement chaque instance de pouvoir se
connecter en réplication avec elle même. La bascule étant automatique, un
ancien primaire rétrogradé en secondaire pourrait se connecter à lui même si
la mécanique d'aiguillage des connexions vers le nouveau primaire n'a pas
encore convergé.

La _timeline_ à l'intérieur des journaux de transaction est mise à jour par le
serveur primaire suite à une promotion de l'instance. Pour que les instances
secondaires se raccrochent à la primaire, il faut leur indiquer d'utiliser la
dernière _timeline_ des journaux de transactions. C'est le rôle du
paramètre `recovery_target_timeline` que l'on doit positionner à `latest`.

:::

-----

### TP: création du cluster PostgreSQL

::: notes

Ce TP a pour but de créer les instances PostgreSQL. Il ne comporte pas de
question, seulement des étapes à suivre.

La configuration de PostgreSQL réalisée ci-dessous est une version simple et
rapide. Elle convient au cadre de ce TP dont le sujet principal est Pacemaker
et PAF, mais ne convient pas pour une utilisation en production.

Dans ce cluster, l'adresse IP virtuelle `10.20.30.5` est associée au
serveur hébergeant l'instance principale.

Créer l'instance primaire sur le nœuds `hanode1` :

~~~console
# /usr/pgsql-12/bin/postgresql-12-setup initdb
Initializing database ... OK
~~~

Configuration de l'instance:

~~~console
# su - postgres

$ cat <<EOF >> ~postgres/12/data/postgresql.conf
listen_addresses = '*'
wal_keep_segments = 32
hba_file = '/var/lib/pgsql/12/pg_hba.conf'
include = '../standby.conf'
EOF

$ cat <<EOF > ~postgres/12/standby.conf
primary_conninfo = 'host=10.20.30.5 application_name=$(hostname -s)'
EOF
~~~

NB: depuis postgres 10, la mise en place de la réplication a été facilitée par
de nouvelles valeurs par défaut pour `wal_level`, `hot_standby`, `max_wal_sender`,
et `max_replication_slots`

NB: avant la version 12, ces paramètres étaient à placer dans un modèle de
configuration (eg. `recovery.conf.pcmk`) nécessaire à PAF.

NB: avant la version 12, il est nécessaire de positionner
`recovery_target_timeline = 'latest'`

Notez que chaque fichier est différent sur chaque nœud grâce à l'utilisation du
hostname local pour l'attribut `application_name`. Ce point fait parti de
pré-requis, est essentiel et doit toujours être vérifié.

Enfin, nous empêchons chaque instance de pouvoir entrer en réplication avec
elle même dans le fichier `pg_hba.conf`. La dernière règle autorise toute autre
connexion de réplication entrante:

~~~console
$ rm ~postgres/12/data/pg_hba.conf
$ cat <<EOF > ~postgres/12/pg_hba.conf
local all         all                     trust
host  all         all      0.0.0.0/0      trust
host  all         all      ::/0           trust

# forbid self-replication from vIP
host  replication postgres 10.20.30.5/32  reject
# forbid self-replication its own IP
host  replication all      $(hostname -s) reject
local replication all                     reject
host  replication all      127.0.0.0/8    reject
host  replication all      ::1/128        reject

# allow any standby connection
host replication postgres 0.0.0.0/0 trust
EOF

$ exit
~~~

NB: les fichiers de configuration propres à chaque instance sont positionnés
hors du `PGDATA`. Ils sont ainsi conservés en cas de reconstruction de
l'instance, ce qui évite des étapes supplémentaires pour les adapter
systématiquement lors de cette procédure.

Suite à cette configuration, nous pouvons démarrer l'instance principale et y
associer l'adresse IP virtuelle choisie pour le primaire:

~~~console
# systemctl start postgresql-12
# ip addr add 10.20.30.5/24 dev eth0
~~~

Cloner l'instance sur les serveurs secondaires `hanode2` et `hanode3`:

~~~console
# su - postgres
$ /usr/pgsql-12/bin/pg_basebackup -h 10.20.30.5 -D ~postgres/12/data/ -P
~~~

Corriger le paramètre `primary_conninfo` sur chaque nœud:

~~~console
$ cat <<EOF > ~postgres/12/standby.conf
primary_conninfo = 'host=10.20.30.5 application_name=$(hostname -s)'
EOF
~~~

Adapter les règles de rejet de la réplication du nœud avec lui même dans `pg_hba.conf`:

~~~console
$ cat <<EOF > ~postgres/12/pg_hba.conf
local all         all                     trust
host  all         all      0.0.0.0/0      trust
host  all         all      ::/0           trust

# forbid self-replication from vIP
host  replication postgres 10.20.30.5/32  reject
# forbid self-replication its own IP
host  replication all      $(hostname -s) reject
local replication all                     reject
host  replication all      127.0.0.0/8    reject
host  replication all      ::1/128        reject

# allow any standby connection
host replication postgres 0.0.0.0/0 trust
EOF
~~~

Démarrer les instances secondaires:

~~~console
$ touch ~postgres/12/data/standby.signal
$ exit
# systemctl start postgresql-12
~~~

NB: avant la version 12 de PostgreSQL, il faut copier le modèle template de
`recovery.conf` (eg. `recovery.conf.pcmk`) dans le `PGDATA` au lieu de créer
le fichier `standby.signal`.

Vérifier le statut de la réplication depuis le serveur primaire :

~~~console
postgres=# TABLE pg_stat_replication;
~~~

Enfin, éteindre tous les services PostgreSQL et les désactiver, comme indiqué
dans les pré-requis. Commencer par le primaire sur `hanode1`.

~~~console
# systemctl disable --now postgresql-12
~~~

Supprimer également l'adresse ip virtuelle ajoutée précédemment, celle-ci est
également contrôlée par Pacemaker par la suite :

~~~console
# ip addr del 10.20.30.5/24 dev eth0
~~~

:::

-----

## Configuration de PAF

* Obligatoire: `PGDATA`
* Paramétrage avant la version 12 : `recovery_template`
* nécessite l'activation des opération `notify`
* Rappel : préciser tous les timeout des opérations
* Rappel : configurer deux opérations `monitor`

::: notes

La configuration de la ressource PostgreSQL est faite avec les paramètres :

* `bindir` : localisation des binaires de PostgreSQL (défaut: `/usr/bin`)
* `pgdata` : localisation du PGDATA de l'instance (défaut: `/var/lib/pgsql/data`)
* `datadir` : chemin du répertoire data_directory si il est différent de `PGDATA`
* `pghost` : le répertoire de socket ou l'adresse IP pour se connecter à l'instance
  locale (défaut: `/tmp` ou `/var/run/postgresql` pour Debian et dérivés)
* `pgport` : le port de l'instance locale (défaut: `5432`)
* `recovery_template` : un template local pour le fichier `PGDATA/recovery.conf`
(défaut: `$PGDATA/recovery.conf.pcmk`)
  * avant PG12 : Ce fichier __doit__ exister sur tous les nœuds ;
  * à partir de PG12 : Ce fichier ne doit exister sur aucun nœuds.
* `start_opts` : Argument supplémentaire à donner au processus PostgreSQL au démarrage
  de PostgreSQL (vide pas défaut).
* `system_user` : l'utilisateur système du propriétaire de l'instance (défaut: `postgres`)
* `maxlag` : lag maximal autorisé pour une standby avant d'y placer un score négatif.
  La différence est calculée entre la position actuelle dans le journal de transaction
  sur le master et la postion écrite sur la standby (défaut: `0`, désactive la
  fonction)

Concernant la configuration des opérations, il est important de rappeler que
les timeout des opérations sont pas défaut de 20 secondes. Voir à ce propos le
chapitre [Création d'une ressource]. Les timeouts précisés dans la description
de l'agent `pgsqlms` ne sont __que__ des valeurs recommandées. Il __faut__
préciser ce timeout en s'inspirant des valeurs conseillées pour __chaque__
opération.

Comme expliqué dans le chapitre [Ressources _Multi-State_], il faut
configurer deux opérations `monitor` distinctes: une pour le rôle `Slave`,
l'autre pour le rôle `Master`. Rappelez-vous que ces opérations doivent avoir
des périodes d'exécution différentes.

Concernant la ressource multi-state prenant en charge les clones, il est
essentiel d'activer les opérations `notify` qui sont désactivées par défaut.
Effectivement, l'agent `pgsqlms` utilise intensément cette opération pour
détecter les cas de _switchover_, de _recovery_, gérer l'élection du
secondaire à promouvoir, etc.

Les différentes opérations pour passer d'un état à l'autre sont deviennent
alors les suivantes:

![Diagramme opérations multi-state avec notify](medias/paf-ms-roles-notify.png)

:::

-----

### TP: création ressource PAF

::: notes

Effectuer les modifications dans un fichier `pgsqld.xml` avant de les appliquer
au cluster.

1. créer une ressource `pgsqld` en précisant:

* les paramètres `bindir` et `pgdata`
* les timeout de toutes les actions. Utiliser les timeout recommandé par
  l'agent
* surveiller le rôle `Master` toutes les 15 secondes
* surveiller le rôle `Slave` toutes les 16 secondes

2. créer la ressource `pgsqld-clone` responsable des clones de `pgsqld`
3. créer la ressource `pgsql-master-ip` gérant l'adresse `10.20.30.5`
4. ajouter une colocation obligatoire entre l'instance primaire de `pgsqld-clone`
   et `pgsql-master-ip`
5. ajouter une contrainte asymétrique pour promouvoir `pgsqld-clone` avant de
   démarrer `pgsql-master-ip`
6. ajouter une contrainte asymétrique pour rétrograder `pgsqld-clone` avant
   d'arrêter `pgsql-master-ip`
7. vérifier la configuration créée puis appliquer la au cluster
8. observer le score `master-pgsqld` des clones `pgsqld`

:::

-----

### Correction: ressource PAF

::: notes

Effectuer les modifications dans un fichier `pgsqld.xml` avant de les appliquer
au cluster.

~~~console
# pcs cluster cib pgsqld.xml
~~~

1. créer une ressource `pgsqld`

~~~console
# pcs -f pgsqld.xml resource create pgsqld ocf:heartbeat:pgsqlms \
    bindir=/usr/pgsql-12/bin pgdata=/var/lib/pgsql/12/data       \
    op start timeout=60s                                         \
    op stop timeout=60s                                          \
    op promote timeout=30s                                       \
    op demote timeout=120s                                       \
    op monitor interval=15s timeout=10s role="Master"            \
    op monitor interval=16s timeout=10s role="Slave"             \
    op notify timeout=60s
~~~

2. créer la ressource `pgsqld-clone` responsable des clones de `pgsqld`

~~~console
# pcs -f pgsqld.xml resource master pgsqld-clone pgsqld notify=true
~~~

Nous ne précisons ici la seule option `notify` qui est __essentielle__ à PAF
et qui est par défaut à `false`. Elle permet d'activer les action `notify`
avant et après chaque action sur la ressource. Nous laissons les autres
options à leur valeur par défaut.

3. créer la ressource `pgsql-master-ip` gérant l'adresse `10.20.30.5`

~~~console
# pcs -f pgsqld.xml resource create pgsql-master-ip ocf:heartbeat:IPaddr2 \
    ip=10.20.30.5 cidr_netmask=24                                         \
    op monitor interval=10s
~~~

4. ajouter une colocation obligatoire entre l'instance primaire de `pgsqld-clone`
   et `pgsql-master-ip`

~~~console
# pcs -f pgsqld.xml constraint \
    colocation add pgsql-master-ip with master pgsqld-clone INFINITY
~~~

5. ajouter une contrainte asymétrique pour promouvoir `pgsqld-clone` avant de
   démarrer `pgsql-master-ip`

~~~console
# pcs -f pgsqld.xml constraint order promote pgsqld-clone \
    then start pgsql-master-ip symmetrical=false kind=Mandatory
~~~

6. ajouter une contrainte asymétrique pour rétrograder `pgsqld-clone`
   avant d'arrêter `pgsql-master-ip`

~~~console
# pcs -f pgsqld.xml constraint order demote pgsqld-clone \
    then stop pgsql-master-ip symmetrical=false kind=Mandatory
~~~

7. vérifier la configuration créée puis appliquer la au cluster

~~~console
# pcs cluster verify -V pgsqld.xml

# crm_simulate -S -x pgsqld.xml

# pcs cluster cib-push pgsqld.xml
~~~

:::

-----

## Master scores de PAF

* mécanique des master scores de PAF
* `1001` pour le primaire
* `1000 - 10 x n` pour les secondaires
* score négatif en cas de décrochage ou retard
* cas du premier démarrage

::: notes

PAF positionne des _master scores_ permanents, qui sont conservés entre les
redémarrage du cluster. Le dernier emplacement du primaire est donc toujours
maintenu au sein du cluster. Il n'est pas recommandé de manipuler soit même
ces scores, nous étudions plus loin les commandes d'administration permettant
d'agir sur l'emplacement du primaire.

Lors du démarrage d'une instance arrêtée alors qu'elle était primaire, l'agent
positionnera son master score à `1` si aucun autre master score n'est connu au
sein du cluster. Les master scores n'étant jamais supprimés par le cluster,
cette mécanique est principalement utile lors du tout premier démarrage.

Une fois la promotion effectuée, le score positionné par l'agent pour assurer
son statu d'instance primaire est de `1001`.

Le score des instances secondaires est mis à jour lors de l'opération `monitor`
sur le primaire. Il peut donc être nécessaire d'attendre un cycle de cette
opération avant que les scores ne soient mis à jour, par exemple, suite à une
bascule. Voici les scores attribués:

* positif: le statut de réplication de l'instance est `stream`
* `-1`: statut de réplication est `startup` ou `backup`
* `-1000`: l'instance n'est pas connectée au primaire
* négatif: l'instance a un lag supérieur au paramètre `max_lag` positionné
sur la ressource `pgsqlms`

Les scores positifs distribués aux secondaires en réplication sont dégressifs
par pas de `10` à partir de `1000`. L'ordre dépend de deux critères: le lag
avec le primaire et le nom de l'instance tel que positionné dans
`application_name`.

Suite au précédent TP, vous devriez observer les scores suivants:

~~~console
# crm_simulate -sL|grep promotion
pgsqld:0 promotion score on hanode1: 1003
pgsqld:1 promotion score on hanode2: 1000
pgsqld:2 promotion score on hanode3: 990
~~~

Tout d'abord, nous observons que le cluster a choisi de démarrer trois clones
en respect de la valeur par défaut du paramètre `clone-max`, positionnée au
nombre de nœuds existants. Ces ressources sont suffixé d'un identifiant:
`pgsqld:0`, `pgsqld:1` et `pgsqld:2`.

Concernant le placement des clones, le cluster actuellement configuré doit
présenter des scores similaires à ceux-ci:

~~~console
# crm_simulate -sL|grep 'native_color: pgsqld'
native_color: pgsqld:0 allocation score on hanode1: 1002
native_color: pgsqld:0 allocation score on hanode2: 0
native_color: pgsqld:0 allocation score on hanode3: 0
native_color: pgsqld:1 allocation score on hanode1: -INFINITY
native_color: pgsqld:1 allocation score on hanode2: 1001
native_color: pgsqld:1 allocation score on hanode3: 0
native_color: pgsqld:2 allocation score on hanode1: -INFINITY
native_color: pgsqld:2 allocation score on hanode2: -INFINITY
native_color: pgsqld:2 allocation score on hanode3: 991
~~~

Les scores `1002`, `1001` et `991` correspondent à la somme des _master scores_
avec le _stickiness_ de `1` associé à la ressource.

Voici pourquoi et comment sont distribués les scores `-INFINITY`:

1. le premier clone `pgsqld:0` pouvait démarrer n'importe où.
2. une fois `pgsqld:0` démarré sur `hanode1`, les clones ne pouvant coexister sur
   le même nœud (`clone-node-max=1`), `pgsqld:1` a un score `-INFINITY` sur
   `hanode1`, mais peu démarrer sur n'importe lequel des deux autres nœuds
3. `pgsqld:2` a un score de `-INFINITY` sur `hanode1` et `hanode2` à cause de la
   présence des deux autres clones. Il ne peut démarrer que sur `hanode3`.

NB: il se peut que vos clones soient répartis différemment.

:::

-----

### TP: étude du premier démarrage

::: notes

Le log de `LRMd` étant configuré en mode debug, les messages de debug de PAF
son visibles dans les log.

1. identifier l'opération `start` dans les log de Pacemaker __sur le primaire__
2. identifier les messages de `pgsqlms` concernant son statut avant et après démarrage
3. identifier la décision de l'agent de positionner son master score
4. identifier sur le DC la décision de créer une nouvelle transition pour
   promouvoir l'instance primaire
5. identifier l'opération de promotion sur le primaire
6. identifier sur le primaire la distributions des scores

:::

-----

### Correction: Étude du premier démarrage

::: notes

Le log de `LRMd` étant configuré en mode debug, les messages de debug de PAF
son visibles dans les log.

1. identifier l'opération `start` dans les log de Pacemaker __sur le primaire__

~~~
lrmd:  info: executing - rsc:pgsqld action:start call_id:27
~~~

2. identifier les messages de `pgsqlms` concernant son statut avant et après démarrage

~~~
pgsqlms(pgsqld) DEBUG: _controldata: instance "pgsqld" state is "shut down"
~~~

Au début de l'opération `start`, `pgsqlms` vérifie toujours le statut de
l'instance en effectuant les mêmes contrôles que l'opération `monitor`. Il
détecte bien ici que l'instance est arrêtée en tant que primaire.

Pour comparaison, une instance secondaire est signalée avec le message suivant:

~~~
pgsqlms(pgsqld)  DEBUG: instance "pgsqld" state is "shut down in recovery"
~~~

Une fois l'opération confirmée, nous constatons bien que le l'instance est
démarrée en tant que standby.

~~~
pgsqlms(pgsqld) DEBUG: _confirm_role: instance pgsqld is a secondary
pgsqlms(pgsqld)  INFO: Instance "pgsqld" started
~~~


3. identifier la décision de l'agent de positionner son master score

~~~
pgsqlms(pgsqld)  INFO: No master score around. Set mine to 1
~~~

Vous remarquerez que ce message n'apparaît sur les autres instances.'

4. identifier sur le DC la décision de créer une nouvelle transition pour
   promouvoir l'instance primaire

~~~
pengine:  debug: pgsqld:1 master score: 1
pengine:   info: Promoting pgsqld:1 (Slave hanode1)
pengine:  debug: pgsqld:0 master score: -1
pengine:  debug: pgsqld:2 master score: -1
pengine:   info: pgsqld-clone: Promoted 1 instances of a possible 1 to master
pengine:  debug: Assigning hanode1 to pgsql-master-ip
[...]
pengine:   info:   Leave    pgsqld:0        (Slave hanode2          )
pengine: notice: * Promote  pgsqld:1        (Slave -> Master hanode1)
pengine:   info:   Leave    pgsqld:2        (Slave hanode3          )
pengine: notice: * Start    pgsql-master-ip (hanode1                )
~~~

Cette transition décide de promouvoir l'instance sur `hanode1` et d'y
démarrer l'adresse IP associée grâce à la colocation créée.

5. identifier l'opération de promotion sur le primaire

~~~
crmd:      info: Performing op=pgsqld_promote_0
lrmd:      info: executing - rsc:pgsqld action:promote
[...]
pgsqlms(pgsqld)[29050]: Mar 20 21:52:40  INFO: Promote complete
lrmd:      info: finished - rsc:pgsqld action:promote exit-code:0
crmd:    notice: Result of promote operation for pgsqld on hanode1: 0 (ok)
~~~

6. identifier sur le primaire la distributions des scores

Une fois la promotion réalisée et avant de la confirmer au cluster, l'agent
vérifie le statut de l'instance de la même manière que l'opération `monitor`.
L'adresse IP n'étant pas encore associée à ce moment là, aucun secondaire n'est
alors connecté.  Vous devriez donc observer les messages suivants:

~~~
pgsqlms(pgsqld) WARNING: No secondary connected to the master
pgsqlms(pgsqld) WARNING: "hanode3" is not connected to the primary
pgsqlms(pgsqld) WARNING: "hanode2" is not connected to the primary
~~~

Au prochain appel à l'opération `monitor`, vous devriez ensuite observer:

~~~
pgsqlms(pgsqld) INFO: Update score of "hanode2" from -1000 to 1000 because of a change in the replication lag (0).
pgsqlms(pgsqld) INFO: Update score of "hanode3" from -1000 to 990 because of a change in the replication lag (0).
~~~

:::

-----

# Administration du cluster

-----

## Démarrer/arrêter le cluster

* pas de mécanique d'arrêt contrôlé et simultané de tous les nœuds
* désactiver les ressources avant d'éteindre le cluster
* au cas par cas ou avec l'option `stop-all-resources`
* utiliser l'attribut de nœuds `standby` pour un nœud isolé

::: notes

Pacemaker n'a pas de mécanique prévue pour interrompre tous les nœuds du
cluster de façon contrôlée. Ainsi, si les nœuds sont éteints les uns après
les autres, quele qu'en soit la raison, le cluster peut avoir le temps de
réagir et planifier des opérations qui pourront être exécutées ou non.

Même avec un outil comme `pcs` qui exécute les commandes d'arrêts sur tous
les nœuds en même temps, il y a toujours un risque de race condition.

À ce propos, voir ce mail et la discussion autour:

<http://lists.clusterlabs.org/pipermail/users/2017-December/006963.html>

Il existe deux solutions pour éteindre le cluster, arrêter les ressources ou
positionner le paramètre de cluster `stop-all-resources` à `true`.

Si l'arrêt ne concerne qu'un seul serveur (eg. mise à jour du noyau, 
évolution matériel, ...), il est possible de le positionner en
« veille » grâce à l'attribut de nœud `standby`. Lorsque cet attribut est
activé sur un nœud, Pacemaker bascule toutes les ressources qu'il héberge
ailleurs dans le cluster et n'en démarrera plus dessus.

:::

-----

### TP: arrêt du cluster

::: notes

1. placer `hanode3` en mode standby
2. observer les contraintes pour `pgsqld-clone`
3. retirer le mode standby de `hanode3`
4. désactiver toutes les ressources
5. éteindre le cluster
6. démarrer le cluster
7. réactiver les ressources.

:::

-----

### Correction: arrêt du cluster

::: notes

1. placer `hanode3` en mode standby

~~~console
# pcs node standby hanode3 --wait
# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 ]
     Stopped: [ hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

Toutes les ressources de `hanode3` ont bien été interrompues.

NOTE: `pcs node standby <node_name>` à remplacé `pcs cluster standby` dans la
version  0.10.1 de pcs.


2. observer les contraintes pour `pgsqld-clone`

~~~console
# pcs constraint location show resource pgsqld-clone
Location Constraints:
~~~

Il n'y a aucune contrainte, le cluster refuse simplement de démarrer une
ressource sur `hanode3`.

3. retirer le mode standby de `hanode3`

~~~console
# pcs node unstandby hanode3 --wait
# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

4. désactiver toutes les ressources

Deux solutions. La première consiste à positionner `stop-all-resources=true`:

~~~console
# pcs property set stop-all-resources=true

# [...] après quelques secondes

# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld]
     Stopped: [ hanode1 hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Stopped
~~~

L'intérêt de se paramètre est que le cluster va interrompre toutes les
ressources en une seule transition:

~~~
pengine:  debug: unpack_config:     Stop all active resources: true
pengine:  debug: native_color:      Forcing fence_vm_hanode1 to stop
pengine:  debug: native_color:      Forcing fence_vm_hanode2 to stop
pengine:  debug: native_color:      Forcing fence_vm_hanode3 to stop
pengine:  debug: native_color:      Forcing pgsqld:1 to stop
pengine:  debug: native_color:      Forcing pgsqld:0 to stop
pengine:  debug: native_color:      Forcing pgsqld:2 to stop
pengine: notice: * Stop fence_vm_hanode1 (        hanode2 )
pengine: notice: * Stop fence_vm_hanode2 (        hanode1 )
pengine: notice: * Stop fence_vm_hanode3 (        hanode1 )
pengine: notice: * Stop pgsqld:0         (  Slave hanode2 )
pengine: notice: * Stop pgsqld:1         ( Master hanode1 )
pengine: notice: * Stop pgsqld:2         (  Slave hanode3 )
pengine: notice: * Stop pgsql-master-ip  (        hanode1 )
~~~

Son désavantage est que le cluster réagit après que le paramètre ait été
positionné. L'outil `pcs` ne peut donc pas attendre la fin de la transition
pour rendre la main, ce qui est gênant dans le cadre d'un script par exemple.

La seconde solution consiste à arrêter chacune des ressources, une à une.
Dans ce cas, nous pouvons demander à `pcs` d'attendre la fin de l'opération,
mais il faut potentiellement exécuter plusieurs commandes donc.

~~~console
# pcs resource disable pgsqld-clone --wait
~~~

5. éteindre le cluster

~~~console
# pcs cluster stop --all
~~~

6. démarrer le cluster

~~~console
# pcs cluster start --all
~~~

7. réactiver les ressources.

Attendre que le cluster soit formé et qu'un DC soit élu.

~~~console
# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld]
     Stopped: [ hanode1 hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Stopped
# pcs property set stop-all-resources=false

[...] après quelques secondes

# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

:::

-----

## Maintenances du cluster

* `maintenance-mode`
  * concerne toutes les ressources
  * désactive toutes les opérations
  * arrête les opérations `monitor`
* `is-managed`
  * ressource par ressource
  * ne désactive pas les opérations `monitor`
  * ne réagit plus aux changements de statut 
* commandes `cleanup` ou `refresh` pour rafraîchir une ressource

::: notes

L'attribut de ressource `is-managed` permet de désactiver les réactions du
cluster pour la ressource concernée. Une fois cet attribut positionné à
`false`, le cluster n'exécute plus aucune nouvelle action de sa propre
initiative. Cependant, les opérations récurrentes de `monitor` sont maintenues.
Un statut différent de celui attendu n'est simplement pas considéré comme une
erreur.

Le paramètre `maintenance-mode` quand à lui permet de placer l'ensemble du
cluster en mode maintenance lorsqu'il est positionné à `true`. Ce paramètre
de cluster concerne __toutes__ les ressources.

Une fois le mode maintenance activé, comme avec l'attribut `is-managed`,
Pacemaker n'exécute plus aucune opération de sa propre initiative, mais il
désactive __aussi__ toutes les opérations récurrentes de `monitor`.

Quelque soit la méthode utilisée pour désactiver temporairement les réactions
du cluster, une fois que ce dernier reprend le contrôle, il compare le statut
des ressources avec celui qu'elles avaient auparavant. Ainsi, si une ressource
a été arrêtée ou déplacée entre temps, il peut déclencher des actions
correctives ! Avant de quitter l'un ou l'autre des modes, veillez à simuler la
réaction du cluster à l'aide de `crm_simulare`.

Lorsque `maintenance-mode` est activé, il peut être utile de demander au
cluster de rafraîchir le statut des ressources. Deux commandes existent:
`crm_ressource --cleanup` ou `crm_ressource --refresh` (et leurs équivalents
avec `pcs`).

La première ne travaille que sur les ressources ayant eu une erreur. Elle
nettoie l'historique des erreurs, les `failcount`, puis exécute une
seule opération `monitor` pour recalculer le statut de la ressource. Elle n'a
aucun effet sur les ressources n'ayant aucune erreur.

La seconde commande effectue les mêmes opérations, travaille aussi sur les
ressources saines et nettoie tout l'historique en plus des erreurs.

:::

-----

### TP: maintenance

::: notes

1. désactiver `is-managed` pour la ressource `pgsqld-clone`
2. arrêter manuellement PostgreSQL sur `hanode2`
3. observer la réaction du cluster
4. exporter la CIB  courante dans le fichier `is-managed.xml` et y activer le
   paramètre `is-managed` pour la ressource `pgsqld-clone` 
5. simuler la réaction du cluster en utilisant la CIB `is-managed.xml` en entrée
6. appliquer la modification de `is-managed.xml` et observer la réaction du
   cluster
7. activer le mode maintenance sur l'ensemble du cluster
8. arrêter manuellement PostgreSQL sur `hanode3`
9. exécuter une commande `cleanup` pour `pgsqld` sur le seul nœud `hanode2`
10. exécuter une commande `cleanup` pour `pgsqld` sur le seul nœud `hanode3`
11. exécuter une commande `refresh` pour `pgsqld` sur le seul nœud `hanode3`
12. simuler la sortie du mode maintenance puis appliquer la modification au
    cluster

:::

-----

### Correction: maintenance

::: notes

1. désactiver `is-managed` pour la ressource `pgsqld-clone`

~~~console
# pcs resource unmanage pgsqld-clone
# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld]
     pgsqld	(ocf::heartbeat:pgsqlms):	Master hanode1 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode2 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode3 (unmanaged)
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

2. arrêter manuellement PostgreSQL sur `hanode2`

Notez que nous ne pouvons pas utiliser `systemctl`. Le service est
désactivé et arrêté aux yeux de systemd.

~~~console
# sudo -iu postgres /usr/pgsql-12/bin/pg_ctl -D /var/lib/pgsql/12/data/ -m fast stop
~~~

3. observer la réaction du cluster

Après quelques secondes, le cluster constate que `pgsqld` est arrêté sur
`hanode2`, mais il ne réagit pas.

~~~console
# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld]
     pgsqld	(ocf::heartbeat:pgsqlms):	Master hanode1 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode3 (unmanaged)
     Stopped: [ hanode2 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

Les log sur le DC présentent bien la non réaction du `pengine`:

~~~
pengine: debug: pgsqld_monitor_16000 on hanode2 returned 'not running' (7) instead of the expected value: 'ok' (0)
pengine:  info: resource pgsqld:1 isn't managed
[...]
pengine: debug: custom_action:    Action pgsqld:0_start_0 (unmanaged)
pengine: debug: custom_action:    Action pgsqld:0_demote_0 (unmanaged)
pengine: debug: custom_action:    Action pgsqld:0_stop_0 (unmanaged)
pengine: debug: custom_action:    Action pgsqld:0_promote_0 (unmanaged)
pengine: debug: custom_action:    Action pgsqld:1_start_0 (unmanaged)
pengine: debug: custom_action:    Action pgsqld:1_stop_0 (unmanaged)
pengine: debug: custom_action:    Action pgsqld:1_start_0 (unmanaged)
pengine:  info: LogActions:       Leave   fence_vm_hanode1        (Started hanode2)
pengine:  info: LogActions:       Leave   fence_vm_hanode2        (Started hanode1)
pengine:  info: LogActions:       Leave   fence_vm_hanode3        (Started hanode1)
pengine:  info: LogActions:       Leave   pgsqld:0        (Master unmanaged)
pengine:  info: LogActions:       Leave   pgsqld:1        (Slave unmanaged)
pengine:  info: LogActions:       Leave   pgsqld:2        (Stopped unmanaged)
pengine:  info: LogActions:       Leave   pgsql-master-ip (Started hanode1)
~~~

4. exporter la CIB  courante dans le fichier `is-managed.xml` et y activer le
paramètre `is-managed` pour la ressource `pgsqld-clone`

~~~console
# pcs cluster cib is-managed.xml
# pcs -f is-managed.xml resource manage pgsqld-clone
~~~

5. simuler la réaction du cluster en utilisant la CIB `is-managed.xml` en entrée

Le cluster décide de redémarrer l'instance sur `hanode2`.

~~~console
# crm_simulate -Sx is-managed.xml 
[...]
Transition Summary:
 * Recover    pgsqld:2     ( Slave hanode2 )  

Executing cluster transition:
 * Pseudo action:   pgsqld-clone_pre_notify_stop_0
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_stop_0
 * Pseudo action:   pgsqld-clone_stop_0
 * Resource action: pgsqld          stop on hanode2
 * Pseudo action:   pgsqld-clone_stopped_0
 * Pseudo action:   pgsqld-clone_post_notify_stopped_0
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_stopped_0
 * Pseudo action:   pgsqld-clone_pre_notify_start_0
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_start_0
 * Pseudo action:   pgsqld-clone_start_0
 * Resource action: pgsqld          start on hanode2
 * Pseudo action:   pgsqld-clone_running_0
 * Pseudo action:   pgsqld-clone_post_notify_running_0
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_running_0
 * Resource action: pgsqld          monitor=16000 on hanode2

Revised cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

6. appliquer la modification de `is-managed.xml` et observer la réaction du cluster

~~~console
# pcs cluster cib-push is-managed.xml
~~~

Le cluster détecte __immédiatement__ un statut différent de celui attendu et
lève une erreur:

~~~console
# pcs resource failcount show pgsqld     
Failcounts for resource 'pgsqld'
  hanode2: 1
~~~

Dans les log du DC:

~~~
pengine:    debug: pgsqld_monitor_16000 on hanode2 returned 'not running' (7) instead of the expected value: 'ok' (0)
pengine:  warning: Processing failed monitor of pgsqld:1 on hanode2: not running | rc=7
pengine:     info:   Start recurring monitor (16s) for pgsqld:1 on hanode2
pengine:     info:   Start recurring monitor (16s) for pgsqld:1 on hanode2
pengine:     info:   Leave   fence_vm_hanode1  (Started hanode2)
pengine:     info:   Leave   fence_vm_hanode2  (Started hanode1)
pengine:     info:   Leave   fence_vm_hanode3  (Started hanode1)
pengine:     info:   Leave   pgsqld:0          (Master hanode1 )
pengine:   notice: * Recover pgsqld:1          (Slave hanode2  )  
pengine:     info:   Leave   pgsqld:2          (Slave hanode3  )
pengine:     info:   Leave   pgsql-master-ip   (Started hanode1)
~~~

7. activer le mode maintenance sur l'ensemble du cluster

Le cluster ne gère plus aucune les ressource.

~~~console
# pcs property set maintenance-mode=true
# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld] (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode3 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Master hanode1 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode2 (unmanaged)
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1 (unmanaged)
~~~

8. arrêter manuellement PostgreSQL sur `hanode3`

~~~console
# sudo -iu postgres /usr/pgsql-12/bin/pg_ctl -D /var/lib/pgsql/12/data/ -m fast stop
~~~

Le cluster ne détecte pas le changement de statut de la ressource.

9. exécuter une commande `cleanup` pour `pgsqld` sur le seul nœud `hanode2`

~~~console
# pcs resource cleanup pgsqld --node=hanode2
Cleaned up pgsqld:0 on hanode2
Cleaned up pgsqld:1 on hanode2
Cleaned up pgsqld:2 on hanode2

# pcs resource failcount show pgsqld
No failcounts for resource 'pgsqld'

# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld] (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode3 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Master hanode1 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode2 (unmanaged)
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1 (unmanaged)
~~~

Nous observons que l'historique des incidents de `pgsqld` sur `hanode2` a disparu.

Le clone `pgsqld` est cependant toujours vu comme démarré sur `hanode3`.

10. exécuter une commande `cleanup` pour `pgsqld` sur le seul nœud `hanode3`

Rien ne change. La commande n'a pas d'effet sur les ressources n'ayant pas eu
d'incident.

~~~console
# pcs resource cleanup pgsqld --node=hanode3
Cleaned up pgsqld:0 on hanode3
Cleaned up pgsqld:1 on hanode3
Cleaned up pgsqld:2 on hanode3

# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld] (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode3 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Master hanode1 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode2 (unmanaged)
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1 (unmanaged)
~~~

11. exécuter une commande `refresh` pour `pgsqld` sur le seul nœud `hanode3`

Le cluster a détecté que la ressource était arrêtée et le consigne dans la
CIB.

~~~console
# pcs resource refresh pgsqld --node=hanode3
Cleaned up pgsqld:0 on hanode3
Cleaned up pgsqld:1 on hanode3
Cleaned up pgsqld:2 on hanode3
Waiting for 3 replies from the CRMd... OK

# pcs resource failcount show pgsqld
No failcounts for resource 'pgsqld'

# pcs resource show 
 Master/Slave Set: pgsqld-clone [pgsqld] (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Master hanode1 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode2 (unmanaged)
     Stopped: [ hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1 (unmanaged)
~~~

12. simuler la sortie du mode maintenance puis appliquer la modification au
cluster

Le cluster prévoie de démarrer l'instance sur `hanode3`

~~~console
# pcs cluster cib maintenance-mode.xml
# pcs -f maintenance-mode.xml property set maintenance-mode=false
# crm_simulate -Sx maintenance-mode.xml
[...]
Transition Summary:
 * Start      pgsqld:2     ( hanode3 )  

Executing cluster transition:
 * Resource action: fence_vm_hanode1 monitor=60000 on hanode2
 * Resource action: fence_vm_hanode2 monitor=60000 on hanode1
 * Resource action: fence_vm_hanode3 monitor=60000 on hanode1
 * Pseudo action:   pgsqld-clone_pre_notify_start_0
 * Resource action: pgsql-master-ip monitor=10000 on hanode1
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_start_0
 * Pseudo action:   pgsqld-clone_start_0
 * Resource action: pgsqld          start on hanode3
 * Pseudo action:   pgsqld-clone_running_0
 * Pseudo action:   pgsqld-clone_post_notify_running_0
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_running_0
 * Resource action: pgsqld          monitor=15000 on hanode1
 * Resource action: pgsqld          monitor=16000 on hanode2
 * Resource action: pgsqld          monitor=16000 on hanode3

Revised cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

Après avoir appliqué la modification sur le cluster, ce dernier démarre
effectivement la ressource, mais aucune erreur n'est levée. Le cluster
s'aperçoit simplement qu'il peut déployer une instance de plus.

~~~console
# pcs cluster cib-push maintenance-mode.xml
# pcs resource failcount show pgsqld
No failcounts for resource 'pgsqld'
~~~

:::

-----

## Simuler des événements

* la commande `crm_simulate` permet de simuler les réactions du cluster
* elle peut aussi injecter des événements, eg.:
  * crash d'un nœud
  * injecter une opération et son code retour, avant transition
  * décider du code retour d'une opération pour la prochaine transition
* chaque appel exécute une seule transition
* possibilité de chaîner les simulations en reprenant le résultat de la précédente
* utile pour analyser les transitions passées

::: notes

Jusqu'à présent l'outil `crm_simulate` a été utilisé pour simuler les
réactions du cluster en fonction d'une situation stable: une CIB de travail
dans un fichier XML que nous manipulons (`crm_simulate -S -x FICHIER`) ou la
CIB en cours d'utilisation par le cluster (`crm_simulate -S -L`).

Il est aussi possible d'utiliser cet outil pour injecter des opérations et
leur code retour grâce à l'argument `--op-inject` ou `-i`. Le format de
l'argument est alors le suivant:
`${resource}_${task}_${interval}@${node}=${rc}`, avec:

* `${resource}`: le nom de la ressource
* `${task}`: l'opération'
* `${interval}`: l'intervalle de récurrence de la commande, en millisecondes
* `${node}`: le nœud sur lequel l'opération est simulée
* `${rc}`: le code retour.

Le code retour doit être précisé de façon numérique. La liste des codes
retours est disponible dans le chapitre [_Ressource Agent_ (_RA_)].

Par exemple, la commande suivante injecte une opération `monitor` indiquant que
la ressource `pgsqld` est arrêtée sur `hanode2`:

~~~
--op-inject=pgsqld_monitor_15000@hanode2=7
~~~

L'argument `--op-fail` ou `-F` permet de prédire le code retour d'une opération
si elle est planifiée durant la simulation. Le format est identique à celui de
`--op-inject`. Il est donc possible d'injecter une opération en entrée de la
simulation avec `--op-inject` et de prédire le code retour d'une ou plusieurs
des opérations planifiées par le cluster en réponse.

D'autres événements sont supportés, tel que l'arrêt d'un nœud ou sa
défaillance (respectivement `--node-down` et `--node-fail`), le changement de
quorum (`--quorum`) ou le retour d'un nœud (`--node-up`).

Quelque soit la simulation effectué, il est utile d'en sauvegarder l'état de
sortie grâce à l'argument `--save-output=FICHIER`. Chaque simulation ne crée
qu'une seule transition. Le fichier obtenu peut donc être réutilisé
directement en entrée d'une autre simulation afin d'étudier les réactions du
cluster suite à la défaillance d'une première transition par exemple.

Ces actions restent cependant de simples simulation, à aucun moment l'agent
n'est exécuté. Ainsi, les éventuels paramètres positionnés par ce dernier
au cours des opérations ne seront pas positionnés. Vous pouvez néanmoins les
positionner vous même dans les fichiers XML de simulation à l'aide des outils
`pcs`, `crm_attribute`, `crm_master`, ...

Enfin, Chaque transition calculée et appliquée en production par le cluster
est enregistrée localement par le `pengine`. Par exemple, dans les log:

~~~
pengine:   notice: Calculated transition 71, saving inputs in /var/lib/pacemaker/pengine/pe-input-135.bz2
~~~

Il est possible d'observer le contenu de cette transition très simplement
grâce à `crm_simulate`, ce qui est utile dans l'analyse d'un événement passé:

~~~console
# crm_simulate --simulate --xml-file /var/lib/pacemaker/pengine/pe-input-135.bz2
Using the original execution date of: 2020-03-26 17:30:27Z

Current cluster status:
[...]
~~~

:::

-----

## Détection de panne

* perte d'un nœud
  * détectée par Corosync
  * immédiatement communiqué à Pacemaker
  * bascules rapides
* le temps de détection d'une panne sur la ressource dépend du `monitor interval`
* la transition calculée dépendent du type et du rôle de la ressource
* le cluster essaie de redémarrer sur le même nœud si possible
* pas de failback automatique

::: notes

En cas de panne, la ressource est arrêtée ou déplacée vers un autre nœud
dans les cas suivants:

* perte totale du nœud où résidait la ressource
* `failcount` de la ressource supérieur ou égal au `migration-threshold`
* erreur retournée par l'opération `monitor` de type `hard`
  (voir [_Ressource Agent_ (_RA_)])
* perte du quorum pour la partition locale

Dans le cas de la perte du nœud, Corosync détecte très rapidement qu'un membre
a quitté le groupe brusquement. Il indique immédiatement à Pacemaker que le
nombre de membre du cluster a changé. La première action de Pacemaker est
habituellement de déclencher un _fencing_ du nœud disparu, au cas où ce dernier
ne soit pas réellement éteint ou qu'il puisse revenir inopinément et rendre le
cluster instable. Les ressources hébergées sur le nœud disparu sont déplacées
une fois le _fencing_ confirmé.

Dans le cas d'une ressource est défaillante, si l'erreur retournée par
l'opération a un niveau de criticité `hard` (voir [_Ressource Agent_ (_RA_)]),
la ressource est démarrée sur un autre nœud.

Dans les autres cas, tant que le `failcount` ne dépasse pas le
`migration-threshold` de la ressource, le cluster tente de redémarrer cette
dernière sur le même nœud (`recovery`).

Que la ressource soit redémarrée sur le même nœud ou déplacée ailleurs,
Pacemaker tente toujours un arrêt (opération `stop`) de celle-ci. Or, si
l'opération `stop` échoue, elle est "promue" en fencing lors de la transition
suivante. Ce comportement est dicté par la propriété `on-fail=fence` de
l'action `stop` (valeur par défaut). Il est __fortement__ déconseillé de
modifier ce comportement.

Les chapitres suivants présentent les réactions du cluster en fonction du
rôle de l'instance: secondaire ou primaire.

De plus, Pacemaker n'a pas d'opération de `failback`. Du reste, ce type
d'opération se prête mal à l'automatisation dans le cadre d'un SGBD. Concernant
PostgreSQL, la procédure de failback est aussi différente en fonction du
rôle de l'instance au moment de la défaillance.

:::

-----

## Défaillance d'un secondaire

* transition: `stop` -> `start`
* cas détecté par l'agent
  * `notify` pré-stop: phase de recovery de PostgreSQL

::: notes

Un incident sur un standby est traité par le cluster par une action `recovery`
qui consiste à enchaîner les deux opérations `stop` et `start` ainsi que les
différentes actions `notify` pré et post opération.

L'agent PAF détecte ces transitions de `recovery` du cluster sur le même nœud.
Il tente alors de corriger le crash de l'instance locale en la démarrant afin
que celle-ci puisse effectuer sa phase de _recovery_ usuelle. Cette opération
est réalisée en tout début de transition durant l'action `notify` pré-stop.

![Primary recovery](medias/paf-standby-recover.png)

:::

-----

### TP: Failover d'un secondaire

::: notes

Supprimer toutes éventuelles contraintes temporaires liées aux TP précédents.

Ce TP simule d'abord un incident sur un secondaire, puis compare la simulation
avec la réalité.

1. positionner le paramètre `migration-threshold` de pgsqld à `2`
2. créer un fichier de simulation `fail-secondary-0.xml` pour travailler dessus
3. injecter une erreur `soft` lors du monitor sur la ressource `pgsqld` de
   `hanode3`. Enregistrer le résultat dans `fail-secondary-1.xml`
4. envoyer un signal SIGKILL aux processus `postgres` sur `hanode3` et vérifier
   le comportement simulé
5. injecter la même erreur en utilisant comme situation de départ
   `fail-secondary-1.xml`
6. Tuer une seconde fois les processus `postgres` sur `hanode3`
7. reproduire en simulation le comportement observé. Enregistrez les
   résultats dans `fail-secondary-2.xml` puis `fail-secondary-3.xml`

:::

-----

### Correction: Failover d'un secondaire

::: notes

Ce TP simule d'abord un incident sur un secondaire, puis compare la simulation
avec la réalité.


1. positionner le paramètre `migration-threshold` de pgsqld à `2`

~~~console
# pcs resource update pgsqld meta migration-threshold=2
~~~

2. créer un fichier de simulation `fail-secondary-0.xml` pour travailler dessus

~~~console
# pcs cluster cib fail-secondary-0.xml
~~~

3. injecter une erreur `soft` lors du monitor sur la ressource `pgsqld` de
   `hanode3`. Enregistrer le résultat dans `fail-secondary-1.xml`

~~~console
# crm_simulate --simulate                    \
  --xml-file=fail-secondary-0.xml            \
  --save-output=fail-secondary-1.xml         \
  --op-inject=pgsqld_monitor_16000@hanode3=1 

Current cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1

Performing requested modifications
 + Injecting pgsqld_monitor_15000@hanode3=1 into the configuration
 + Injecting attribute fail-count-pgsqld#monitor_15000=value++ into /node_state '3'
 + Injecting attribute last-failure-pgsqld#monitor_15000=1585235516 into /node_state '3'

Transition Summary:
 * Recover    pgsqld:0     ( Slave hanode3 )  

Executing cluster transition:
 * Cluster action:  clear_failcount for pgsqld on hanode3
 * Pseudo action:   pgsqld-clone_pre_notify_stop_0
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_stop_0
 * Pseudo action:   pgsqld-clone_stop_0
 * Resource action: pgsqld          stop on hanode3
 * Pseudo action:   pgsqld-clone_stopped_0
 * Pseudo action:   pgsqld-clone_post_notify_stopped_0
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_stopped_0
 * Pseudo action:   pgsqld-clone_pre_notify_start_0
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_start_0
 * Pseudo action:   pgsqld-clone_start_0
 * Resource action: pgsqld          start on hanode3
 * Pseudo action:   pgsqld-clone_running_0
 * Pseudo action:   pgsqld-clone_post_notify_running_0
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_running_0
 * Resource action: pgsqld          monitor=16000 on hanode3

Revised cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

Le cluster redémarre l'instance sur le même nœud. Son `failcount` est
incrémenté de `1`.

La transition effectue bien une action `stop` suivie d'une action `start`.

~~~console
# pcs -f fail-secondary-1.xml resource failcount show pgsqld     
Failcounts for resource 'pgsqld'
  hanode3: 1
~~~

4. envoyer un signal `SIGKILL` aux processus `postgres` sur `hanode3` et vérifier
   le comportement simulé

~~~console
# pkill -SIGKILL postgres
~~~

Le comportement simulé est bien le même que celui observé.

~~~console
# pcs resource failcount show pgsqld
Failcounts for resource 'pgsqld'
  hanode3: 1

# pcs resource show 
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

5. injecter la même erreur en utilisant comme situation de départ
   `fail-secondary-1.xml`

~~~console
# crm_simulate --simulate                      \
    --xml-file=fail-secondary-1.xml            \
    --save-output=fail-secondary-2.xml         \
    --op-inject=pgsqld_monitor_16000@hanode3=1 

Current cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1

Performing requested modifications
 + Injecting pgsqld_monitor_16000@hanode3=1 into the configuration
 + Injecting attribute fail-count-pgsqld#monitor_16000=value++ into /node_state '3'
 + Injecting attribute last-failure-pgsqld#monitor_16000=1585243357 into /node_state '3'

Transition Summary:
 * Stop       pgsqld:0     ( Slave hanode3 )   due to node availability

Executing cluster transition:
 * Cluster action:  clear_failcount for pgsqld on hanode3
 * Pseudo action:   pgsqld-clone_pre_notify_stop_0
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_stop_0
 * Pseudo action:   pgsqld-clone_stop_0
 * Resource action: pgsqld          stop on hanode3
 * Pseudo action:   pgsqld-clone_stopped_0
 * Pseudo action:   pgsqld-clone_post_notify_stopped_0
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_stopped_0

Revised cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 ]
     Stopped: [ hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

Le `failcount` ayant atteint la valeur de `migration-threshold`, la ressource
doit quitter le nœud. Néanmoins, tous les autres nœuds possédant déjà un
clone et le paramètre `clone-node-max` étant à `1`, ce troisème clone ne peut
démarrer nulle part.

~~~console
# pcs -f fail-secondary-2.xml resource failcount show pgsqld
Failcounts for resource 'pgsqld'
  hanode3: 2
~~~

6. Tuer une seconde fois les processus `postgres` sur `hanode3`

~~~console
# pkill -SIGKILL postgres
~~~

Cette fois-ci, le comportement est différent. La ressource n'est pas
simplement isolée, c'est tout le nœud `hanode3` est isolé.

~~~console
# pcs status nodes 
Pacemaker Nodes:
 Online: hanode1 hanode2
 Standby:
 Maintenance:
 Offline: hanode3
[...]
~~~

Les log de `hanode3` montrent les erreurs suivantes:

~~~
lrmd[3248]:    info: executing - rsc:pgsqld action:stop call_id:85
pgsqlms(pgsqld): ERROR: Instance "pgsqld" controldata indicates a running secondary instance, the instance has probably crashed
pgsqlms(pgsqld): ERROR: Unexpected state for instance "pgsqld" (returned 1)
lrmd[3248]:    info: finished - rsc:pgsqld action:stop call_id:85 pid:9962 exit-code:1 exec-time:161ms queue-time:0ms
~~~

L'agent PAF est très stricte et contrôle l'état de l'instance avant chaque
opération. Lors de l'opération stop, il détecte que l'instance se trouve
dans un état incohérent et lève alors une erreur.

À partir de cette erreur, les log du DC présentent les messages suivants:

~~~
crmd:  warning: status_from_rc:    Action 2 (pgsqld_stop_0) on hanode3 failed (target: 0 vs. rc: 1): Error

pengine: warning: Processing failed stop of pgsqld:0 on hanode3: unknown error | rc=1
pengine: warning: Cluster node hanode3 will be fenced: pgsqld:0 failed there
pengine: warning: Scheduling Node hanode3 for STONITH
pengine:  notice: Stop of failed resource pgsqld:0 is implicit after hanode3 is fenced
pengine:  notice: * Fence (reboot) hanode3 'pgsqld:0 failed there'
pengine:    info:   Leave   fence_vm_hanode1  (Started hanode2)
pengine:    info:   Leave   fence_vm_hanode2  (Started hanode1)
pengine:    info:   Leave   fence_vm_hanode3  (Started hanode1)
pengine:  notice: * Stop       pgsqld:0       (Slave hanode3  )
pengine:    info:   Leave   pgsqld:1          (Master hanode1)
pengine:    info:   Leave   pgsqld:2          (Slave hanode2)
pengine:    info:   Leave   pgsql-master-ip   (Started hanode1)
pengine: warning: Calculated transition 75 (with warnings), saving inputs in /var/lib/pacemaker/pengine/pe-warn-0.bz2

crmd:   notice: te_fence_node:     Requesting fencing (reboot) of node hanode3
stonith-ng:   notice: initiate_remote_stonith_op:        Requesting peer fencing (reboot) of hanode3
stonith-ng:   notice: crm_update_peer_state_iter:        Node hanode3 state is now lost | nodeid=3 previous=member source=crm_update_peer_proc
crmd:   notice: crm_update_peer_state_iter:        Node hanode3 state is now lost
~~~

Une nouvelle transition est calculée et l'opération `stop` est "promue" en
fencing.

7. reproduire en simulation le comportement observé. Enregistrez les
   résultats dans `fail-secondary-2.xml` puis `fail-secondary-3.xml`

~~~console
# crm_simulate --simulate                      \
    --xml-file=fail-secondary-1.xml            \
    --save-output=fail-secondary-2.xml         \
    --op-inject=pgsqld_monitor_16000@hanode3=1 \
    --op-fail=pgsqld_stop_0@hanode3=1
[...]
Performing requested modifications
 + Injecting pgsqld_monitor_16000@hanode3=1 into the configuration
 + Injecting attribute fail-count-pgsqld#monitor_16000=value++ into /node_state '3'
 + Injecting attribute last-failure-pgsqld#monitor_16000=1585245905 into /node_state '3'

Transition Summary:
 * Stop       pgsqld:0     ( Slave hanode3 )   due to node availability

Executing cluster transition:
 * Cluster action:  clear_failcount for pgsqld on hanode3
 * Pseudo action:   pgsqld-clone_pre_notify_stop_0
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_stop_0
 * Pseudo action:   pgsqld-clone_stop_0
 * Resource action: pgsqld          stop on hanode3
	Pretending action 2 failed with rc=1
 + Injecting attribute fail-count-pgsqld#stop_0=value++ into /node_state '3'
 + Injecting attribute last-failure-pgsqld#stop_0=1585245905 into /node_state '3'
 * Pseudo action:   pgsqld-clone_stopped_0
 * Pseudo action:   pgsqld-clone_post_notify_stopped_0
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_stopped_0

Revised cluster status:
Node hanode3 (3): UNCLEAN (online)
Online: [ hanode1 hanode2 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     pgsqld	(ocf::heartbeat:pgsqlms):	FAILED hanode3
     Masters: [ hanode1 ]
     Slaves: [ hanode2 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1

# crm_simulate --simulate                      \
    --xml-file=fail-secondary-2.xml            \
    --save-output=fail-secondary-3.xml

Current cluster status:
Node hanode3 (3): UNCLEAN (online)
Online: [ hanode1 hanode2 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     pgsqld	(ocf::heartbeat:pgsqlms):	FAILED hanode3
     Masters: [ hanode1 ]
     Slaves: [ hanode2 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1

Transition Summary:
 * Fence (reboot) hanode3 'pgsqld:0 failed there'
 * Stop       pgsqld:0     ( Slave hanode3 )   due to node availability

Executing cluster transition:
 * Pseudo action:   pgsqld-clone_pre_notify_stop_0
 * Fencing hanode3 (reboot)
 * Pseudo action:   pgsqld_post_notify_stop_0
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_stop_0
 * Pseudo action:   pgsqld-clone_stop_0
 * Pseudo action:   pgsqld_stop_0
 * Pseudo action:   pgsqld-clone_stopped_0
 * Pseudo action:   pgsqld-clone_post_notify_stopped_0
 * Resource action: pgsqld          notify on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_stopped_0
 * Pseudo action:   pgsqld_notified_0

Revised cluster status:
Online: [ hanode1 hanode2 ]
OFFLINE: [ hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 ]
     Stopped: [ hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

:::

-----

## Failback d'un secondaire

* suite à un incident sur la ressource ou la perte de son nœud
* état incohérent de l'instance: statut différent du `pg_control`
* PAF lève une erreur systématiquement pour toutes les opérations
* une erreur sur l'action `stop` conduit à un fencing
* conclusion: placer l'instance dans un état stable
1. positionner la ressource en `is-managed=false`
2. ré-intégrer le nœud dans le cluster
3. démarrer la ressource manuellement, puis l'arrêter (état stable)
4. effectuer un `refresh` de la ressource
5. positionner `is-managed=true` pour la ressource

::: notes

Suite au crash d'une instance secondaire, si le cluster n'a pas réussi à
l'arrêter localement, le serveur entier a dû être isolé (cf TP
[Correction: Défaillance d'un secondaire]). L'instance est alors dans un état
instable: son fichier interne `pg_control` indique un statut `in archive
recovery` alors que cette dernière n'est pas démarrée et n'accepte aucune
connexion.

Dans cette situation, l'agent retourne une erreur pour toutes les opérations.
Au démarrage du cluster sur le nœud concerné, ce dernier va vouloir
contrôler l'état des ressources sur ce nœud et l'opération de `probe`
(l'opération `monitor` non récurrente) va retourner une erreur.

Il est même possible que le cluster tente d'effectuer un `recovery` de la
ressource en effectuant les opérations `stop` puis `start`. Dans ce cas là,
le nœud se fait une nouvelle fois isoler.

Pour ré-intégrer le nœud et la ressource, l'idéal est de suivre la
procédure suivante:

1. positionner `is-managed=false` pour la ressource
2. démarrer le cluster sur le nœud à ré-intégrer
3. démarrer manuellement l'instance sur le nœud
4. valider que cette dernière réplique correctement
5. arrêter l'instance
6. effectuer une commande `refresh` de la ressource
7. supprimer `is-managed=false` pour la ressource

Pour plus de facilité, il est possible d'utiliser ici `systemctl` pour
démarrer et arrêter la ressource. L'important est qu'en fin de procédure,
`systemd` ne voit pas l'instance comme étant démarrée de son point vue,
cette dernière étant gérée non pas par lui mais par Pacemaker.

:::

-----

### TP: Failback d'un secondaire

::: notes

1. désactiver la gestion du cluster de `pgsqld-clone`
2. démarrer le cluster sur `hanode3`
3. démarrer manuellement l'instance PostgreSQL sur `hanode3`
4. valider que cette dernière réplique correctement
5. arrêter l'instance
6. effectuer une commande `refresh` de `pgsqld`
7. supprimer `is-managed=false` pour la ressource

:::

-----

### Correction: Failback d'un secondaire

::: notes

1. désactiver la gestion du cluster de `pgsqld-clone`

~~~console
# pcs resource unmanage pgsqld-clone
~~~

2. démarrer le cluster sur `hanode3`

~~~console
# pcs cluster start
~~~

Attendre que le nœud soit bien ré-intégré dans le cluster.

3. démarrer manuellement l'instance PostgreSQL sur `hanode3`

~~~console
# systemctl start postgresql-12
~~~

4. valider que cette dernière réplique correctement

Depuis l'instance primaire, la ressource est détectée comme démarrée et
PostgreSQL nous indique qu'elle réplique correctement:

~~~console
# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld]
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode2 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode3 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Master hanode1 (unmanaged)
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
 
# sudo -iu postgres psql
postgres=# select state, application_name
  from pg_stat_replication
  where application_name = 'hanode3'; 
   state   | application_name 
-----------+------------------
 streaming | hanode3
(1 row)
~~~

5. arrêter l'instance

~~~console
# systemctl stop postgresql-12
# systemctl show -p ActiveState postgresql-12
ActiveState=inactive
~~~

Après vérification, plus aucun processus `postgres` n'est démarré. Son
statut est cohérent:

~~~console
# /usr/pgsql-12/bin/pg_controldata /var/lib/pgsql/12/data/|grep state
Database cluster state:               shut down in recovery
~~~

6. effectuer une commande `refresh` de `pgsqld`

~~~console
# pcs resource failcount show pgsqld hanode3
Failcounts for resource 'pgsqld' on node 'hanode3'
  hanode3: 3

# pcs resource refresh pgsqld --node=hanode3
Cleaned up pgsqld:0 on hanode3
Cleaned up pgsqld:1 on hanode3
Cleaned up pgsqld:2 on hanode3

  * The configuration prevents the cluster from stopping or starting 'pgsqld-clone' (unmanaged)
Waiting for 3 replies from the CRMd... OK

# pcs resource failcount show pgsqld hanode3
No failcounts for resource 'pgsqld' on node 'hanode3'
~~~

Toutes les erreurs sont supprimées et le failcount est remis à 0.

7. supprimer `is-managed=false` pour la ressource

~~~console
# pcs resource manage pgsqld-clone
~~~

La ressource est démarrée sur `hanode3`.

:::

-----

##  Défaillance du primaire

1. transaction calculée
  * `demote` -> `stop` -> `start` -> `promote`
2. fencing du nœud hébergeant l'instance primaire en échec si nécessaire
3. si migration, promotion du secondaire avec le meilleur master score
  1. le secondaire désigné compare les `LSN` des secondaires
  2. poursuite de la promotion s'il est toujours le plus avancé
  3. sinon, annulation de la promotion et nouvelle transition

::: notes

En cas d'incident concernant l'instance primaire, la transition calculée
effectue les quatre opérations suivantes dans cet ordre: `demote`, `stop`,
`start` et `promote`. Ici aussi, les différentes actions `notify` pré et post
opération sont bien entendu exécutées.

Comme pour un secondaire, l'agent PAF détecte une transition effectuant ces
opérations sur l'instance primaire sur un même nœud. Dans ce cas là, l'agent
tente alors de corriger le crash de l'instance locale en la démarrant afin que
celle-ci puisse effectuer sa phase de _recovery_ usuelle. Cette opération est
réalisée en tout début de transition durant l'action `notify` pré-demote.

![Primary recovery](medias/paf-primary-recover.png)

Le choix de l'instance à promouvoir se fait en fonction des derniers master
scores connus. Afin de s'assurer que le secondaire désigné est bien toujours le
plus avancé dans la réplication, une élection est cependant déclenchée. En
voici les étapes:

1. opération `notify` pré-promote: chaque secondaire positionne son `LSN`
   courant dans un attribut de nœud
2. opération `promote`: l'instance désignée pour la promotion vérifie qu'il a
   bien le LSN le plus avancé
3. si un LSN plus avancé est trouvé:
   * il positionne son master score à `1`
   * il positionne le master score du secondaire plus avancé à `1000`
   * il lève une erreur
   * la transition est annulée et une nouvelle est calculée
   * retour à l'étape 1.

![Primary recovery](medias/paf-election.png)

:::

-----

### TP: Failover du primaire

::: notes

1. simuler une erreur `soft` pour `pgsqld-clone` sur `hanode1`
2. tuer tous les processus PostgreSQL avec un signal `KILL`
3. étudier la réaction du cluster
4. nettoyer les `failcount` de `pgsqld-clone`
5. simuler une erreur `OCF_ERR_ARGS` sur `pgsqld-clone`
6. supprimer le fichier `/var/lib/pgsql/12/data/global/pg_control` sur `hanode1`
7. étudier la réaction du cluster

:::

-----

### Correction: Failover du primaire

::: notes

1. simuler une erreur `soft` pour `pgsqld-clone` sur `hanode1`

~~~console
# crm_simulate --simulate --live --op-inject=pgsqld_monitor_15000@hanode1=1  

Current cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1

Performing requested modifications
 + Injecting pgsqld_monitor_15000@hanode1=1 into the configuration
 + Injecting attribute fail-count-pgsqld#monitor_15000=value++ into /node_state '1'
 + Injecting attribute last-failure-pgsqld#monitor_15000=1585328861 into /node_state '1'

Transition Summary:
 * Recover    pgsqld:2     ( Master hanode1 )  

Executing cluster transition:
 * Cluster action:  clear_failcount for pgsqld on hanode1
 * Pseudo action:   pgsqld-clone_pre_notify_demote_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_demote_0
 * Pseudo action:   pgsqld-clone_demote_0
 * Resource action: pgsqld          demote on hanode1
 * Pseudo action:   pgsqld-clone_demoted_0
 * Pseudo action:   pgsqld-clone_post_notify_demoted_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_demoted_0
 * Pseudo action:   pgsqld-clone_pre_notify_stop_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_stop_0
 * Pseudo action:   pgsqld-clone_stop_0
 * Resource action: pgsqld          stop on hanode1
 * Pseudo action:   pgsqld-clone_stopped_0
 * Pseudo action:   pgsqld-clone_post_notify_stopped_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_stopped_0
 * Pseudo action:   pgsqld-clone_pre_notify_start_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_start_0
 * Pseudo action:   pgsqld-clone_start_0
 * Resource action: pgsqld          start on hanode1
 * Pseudo action:   pgsqld-clone_running_0
 * Pseudo action:   pgsqld-clone_post_notify_running_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_running_0
 * Pseudo action:   pgsqld-clone_pre_notify_promote_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_promote_0
 * Pseudo action:   pgsqld-clone_promote_0
 * Resource action: pgsqld          promote on hanode1
 * Pseudo action:   pgsqld-clone_promoted_0
 * Pseudo action:   pgsqld-clone_post_notify_promoted_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_promoted_0
 * Resource action: pgsqld          monitor=15000 on hanode1

Revised cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1
~~~

Un `recover` est planifié pour `pgsqld` sur `hanode1`. Ce dernier correspond
aux opérations suivantes dans cet ordre:

Action      Sub-action    Nœud(s)
----------  ------------  ---------------------------------
 `notify`    pre-demote    `hanode1`, `hanode2`, `hanode3`
 `demote`    N/A           `hanode1`
 `notify`    post-demote   `hanode1`, `hanode2`, `hanode3`
 `notify`    pre-stop      `hanode1`, `hanode2`, `hanode3`
 `stop`      N/A           `hanode1`
 `notify`    post-stop     `hanode2`, `hanode3`
 `notify`    pre-start     `hanode2`, `hanode3`
 `start`     N/A           `hanode1`
 `notify`    post-start    `hanode1`, `hanode2`, `hanode3`
 `notify`    pre-promote   `hanode1`, `hanode2`, `hanode3`
 `promote`   N/A           `hanode1`
 `notify`    post-promote  `hanode1`, `hanode2`, `hanode3`

2. tuer tous les processus PostgreSQL avec un signal `KILL`

~~~console
# pkill -SIGKILL postgres
~~~

3. étudier la réaction du cluster

L'agent `pgsqlms` détecte que l'instance a a été interrompue brusquement:

~~~
pgsqlms(pgsqld): DEBUG: _confirm_stopped: no postmaster process found for instance "pgsqld"
pgsqlms(pgsqld): DEBUG: _controldata: instance "pgsqld" state is "in production"
pgsqlms(pgsqld): ERROR: Instance "pgsqld" controldata indicates a running primary instance, the instance has probably crashed
~~~

En réaction, `pengine` décide de redémarrer l'instance sur le même nœud
(sur le DC):

~~~
pengine:   info:   Start recurring monitor (15s) for pgsqld:1 on hanode1
pengine:   info:   Leave   fence_vm_hanode1 (Started hanode2)
pengine:   info:   Leave   fence_vm_hanode2 (Started hanode1)
pengine:   info:   Leave   fence_vm_hanode3 (Started hanode1)
pengine:   info:   Leave   pgsqld:0         (Slave hanode2  )
pengine: notice: * Recover pgsqld:1         (Master hanode1 )
pengine:   info:   Leave   pgsqld:2         (Slave hanode3  )
pengine:   info:   Leave   pgsql-master-ip  (Started hanode1)
~~~

Durant l'opération `notify` pré-demote, l'agent tente un recovery de
l'instance afin de la remettre en ordre de marche:

~~~
pgsqlms(pgsqld): INFO: Trying to start failing master "pgsqld"...
[...]            
pgsqlms(pgsqld): INFO: State is "in production" after recovery attempt
~~~

Le reste de la transition se déroule comme prévu et l'instance revient bien
en production. Le comportement est bien le même que celui simulé. Voici les
actions déclenchées par le DC (log remis en forme):

~~~
# grep -E 'crmd:.*Initiating' /var/log/cluster/corosync.log
[...]
crmd:  notice: Initiating notify  pgsqld_pre_notify_demote_0   on hanode1
crmd:  notice: Initiating notify  pgsqld_pre_notify_demote_0   on hanode2
crmd:  notice: Initiating notify  pgsqld_pre_notify_demote_0   on hanode3

crmd:  notice: Initiating demote  pgsqld_demote_0 locally      on hanode1

crmd:  notice: Initiating notify  pgsqld_post_notify_demote_0  on hanode1
crmd:  notice: Initiating notify  pgsqld_post_notify_demote_0  on hanode2
crmd:  notice: Initiating notify  pgsqld_post_notify_demote_0  on hanode3

crmd:  notice: Initiating notify  pgsqld_pre_notify_stop_0     on hanode1
crmd:  notice: Initiating notify  pgsqld_pre_notify_stop_0     on hanode2
crmd:  notice: Initiating notify  pgsqld_pre_notify_stop_0     on hanode3

crmd:  notice: Initiating stop    pgsqld_stop_0 locally        on hanode1

crmd:  notice: Initiating notify  pgsqld_post_notify_stop_0    on hanode2
crmd:  notice: Initiating notify  pgsqld_post_notify_stop_0    on hanode3

crmd:  notice: Initiating notify  pgsqld_pre_notify_start_0    on hanode2
crmd:  notice: Initiating notify  pgsqld_pre_notify_start_0    on hanode3

crmd:  notice: Initiating start   pgsqld_start_0 locally       on hanode1

crmd:  notice: Initiating notify  pgsqld_post_notify_start_0   on hanode1
crmd:  notice: Initiating notify  pgsqld_post_notify_start_0   on hanode2
crmd:  notice: Initiating notify  pgsqld_post_notify_start_0   on hanode3

crmd:  notice: Initiating notify  pgsqld_pre_notify_promote_0  on hanode1
crmd:  notice: Initiating notify  pgsqld_pre_notify_promote_0  on hanode2
crmd:  notice: Initiating notify  pgsqld_pre_notify_promote_0  on hanode3

crmd:  notice: Initiating promote pgsqld_promote_0 locally     on hanode1

crmd:  notice: Initiating notify  pgsqld_post_notify_promote_0 on hanode1
crmd:  notice: Initiating notify  pgsqld_post_notify_promote_0 on hanode2
crmd:  notice: Initiating notify  pgsqld_post_notify_promote_0 on hanode3
~~~

4. nettoyer les `failcount` de `pgsqld-clone`

~~~console
# pcs resource failcount reset pgsqld
~~~

5. simuler une erreur `OCF_ERR_ARGS` sur `pgsqld-clone`

Le code retour `OCF_ERR_ARGS` correspond à une erreur de niveau `hard`. Ainsi,
bien que le `migration-threshold` ne soit pas atteint, le cluster doit basculer
l'instance ailleurs.

~~~console
# crm_simulate --simulate --live --op-inject=pgsqld_monitor_15000@hanode1=2 

Current cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode1 ]
     Slaves: [ hanode2 hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode1

Performing requested modifications
 + Injecting pgsqld_monitor_15000@hanode1=2 into the configuration
 + Injecting attribute fail-count-pgsqld#monitor_15000=value++ into /node_state '1'
 + Injecting attribute last-failure-pgsqld#monitor_15000=1585330828 into /node_state '1'

Transition Summary:
 * Promote    pgsqld:0            ( Slave -> Master hanode2 )  
 * Stop       pgsqld:2            (          Master hanode1 )   due to node availability
 * Move       pgsql-master-ip     (      hanode1 -> hanode2 )  

Executing cluster transition:
 * Resource action: pgsqld          cancel=16000 on hanode2
 * Cluster action:  clear_failcount for pgsqld on hanode1
 * Pseudo action:   pgsqld-clone_pre_notify_demote_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_demote_0
 * Pseudo action:   pgsqld-clone_demote_0
 * Resource action: pgsqld          demote on hanode1
 * Pseudo action:   pgsqld-clone_demoted_0
 * Pseudo action:   pgsqld-clone_post_notify_demoted_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_demoted_0
 * Pseudo action:   pgsqld-clone_pre_notify_stop_0
 * Resource action: pgsql-master-ip stop on hanode1
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Resource action: pgsqld          notify on hanode1
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_stop_0
 * Pseudo action:   pgsqld-clone_stop_0
 * Resource action: pgsqld          stop on hanode1
 * Pseudo action:   pgsqld-clone_stopped_0
 * Pseudo action:   pgsqld-clone_post_notify_stopped_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_stopped_0
 * Pseudo action:   pgsqld-clone_pre_notify_promote_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Pseudo action:   pgsqld-clone_confirmed-pre_notify_promote_0
 * Pseudo action:   pgsqld-clone_promote_0
 * Resource action: pgsqld          promote on hanode2
 * Pseudo action:   pgsqld-clone_promoted_0
 * Pseudo action:   pgsqld-clone_post_notify_promoted_0
 * Resource action: pgsqld          notify on hanode2
 * Resource action: pgsqld          notify on hanode3
 * Pseudo action:   pgsqld-clone_confirmed-post_notify_promoted_0
 * Resource action: pgsql-master-ip start on hanode2
 * Resource action: pgsqld          monitor=15000 on hanode2
 * Resource action: pgsql-master-ip monitor=10000 on hanode2

Revised cluster status:
Online: [ hanode1 hanode2 hanode3 ]

 fence_vm_hanode1	(stonith:fence_virsh):	Started hanode2
 fence_vm_hanode2	(stonith:fence_virsh):	Started hanode1
 fence_vm_hanode3	(stonith:fence_virsh):	Started hanode1
 Master/Slave Set: pgsqld-clone [pgsqld]
     Masters: [ hanode2 ]
     Slaves: [ hanode3 ]
     Stopped: [ hanode1 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode2
~~~

6. supprimer le fichier `/var/lib/pgsql/12/data/global/pg_control` sur `hanode1`

~~~console
# rm -f /var/lib/pgsql/12/data/global/pg_control
~~~

7. étudier la réaction du cluster

Le cluster prévoie la même transition que celle simulée. Cependant, à cause
de l'état incohérent de l'instance, les opération `demote` et `stop`
interrompent deux transitions et la dernière erreur provoque l'isolation de
`hanode1`.

Première transition, correspondant à ce qui avait été simulé:

~~~
pengine: notice: * Stop    pgsqld:0        (            Master hanode1 )
pengine:   info:   Leave   pgsqld:1        (             Slave hanode3 )
pengine: notice: * Promote pgsqld:2        (   Slave -> Master hanode2 )
pengine: notice: * Move    pgsql-master-ip (        hanode1 -> hanode2 )

crmd:   debug:  Unpacked transition 136: 41 actions in 41 synapses

crmd:  notice:  Initiating notify  pgsqld_pre_notify_demote_0   on hanode1
crmd:  notice:  Initiating notify  pgsqld_pre_notify_demote_0   on hanode2
crmd:  notice:  Initiating notify  pgsqld_pre_notify_demote_0   on hanode3

crmd:  notice:  Initiating demote  pgsqld_demote_0              on hanode1
crmd: warning:  Action 15 (pgsqld_demote_0) on hanode2 failed

crmd:  notice:  Initiating notify  pgsqld_post_notify_demote_0  on hanode1
crmd:  notice:  Initiating notify  pgsqld_post_notify_demote_0  on hanode2
crmd:  notice:  Initiating notify  pgsqld_post_notify_demote_0  on hanode3
~~~

La seconde transition prévoit de terminer l'arrêt de l'instance sur `hanode1`
puis d'effectuer la promotion sur `hanode2`. Elle termine en erreur sur
l'opération `stop`:

~~~
pengine: notice: * Stop    pgsqld:0        (             Slave hanode1 )
pengine:   info:   Leave   pgsqld:1        (             Slave hanode3 )
pengine: notice: * Promote pgsqld:2        (   Slave -> Master hanode2 )
pengine: notice: * Stop    pgsql-master-ip (                   hanode1 )

crmd:   debug:  Unpacked transition 137: 24 actions in 24 synapses

crmd:  notice:  Initiating notify  pgsqld_pre_notify_stop_0     on hanode1
crmd:  notice:  Initiating notify  pgsqld_pre_notify_stop_0     on hanode2
crmd:  notice:  Initiating notify  pgsqld_pre_notify_stop_0     on hanode3

crmd:  notice:  Initiating stop    pgsqld_stop_0                on hanode1
crmd: warning:  Action 3 (pgsqld_stop_0) on hanode1 failed

crmd:  notice:  Initiating notify  pgsqld_post_notify_stop_0    on hanode3
crmd:  notice:  Initiating notify  pgsqld_post_notify_stop_0    on hanode2
~~~

La troisième transition prévoie d'isoler `hanode1` afin de s'assurer que
l'instance est bien arrêtée, puis de promouvoir l'instance sur `hanode2` et y
déplacer l'adresse IP virtuelle. Cette dernière arrive au bout:

~~~
pengine:  notice: * Fence (reboot) hanode2 'pgsqld:0 failed there'
pengine:  notice: * Stop    pgsqld:0        (            Master hanode1 )
pengine:    info:   Leave   pgsqld:1        (             Slave hanode3 )
pengine:  notice: * Promote pgsqld:2        (   Slave -> Master hanode2 )
pengine:  notice: * Move    pgsql-master-ip (        hanode2 -> hanode2 )

crmd:   debug:  Unpacked transition 138: 43 actions in 43 synapses

crmd:  notice:  Initiating notify  pgsqld_pre_notify_demote_0   on hanode3
crmd:  notice:  Initiating notify  pgsqld_pre_notify_demote_0   on hanode2

crmd:  notice:  Initiating notify  pgsqld_post_notify_demote_0  on hanode3
crmd:  notice:  Initiating notify  pgsqld_post_notify_demote_0  on hanode2

crmd:  notice:  Initiating notify  pgsqld_pre_notify_stop_0     on hanode3
crmd:  notice:  Initiating notify  pgsqld_pre_notify_stop_0     on hanode2

crmd:  notice:  Initiating notify  pgsqld_post_notify_stop_0    on hanode3
crmd:  notice:  Initiating notify  pgsqld_post_notify_stop_0    on hanode2

crmd:  notice:  Initiating notify  pgsqld_pre_notify_promote_0  on hanode3
crmd:  notice:  Initiating notify  pgsqld_pre_notify_promote_0  on hanode2

crmd:  notice:  Initiating promote pgsqld_promote_0             on hanode2

crmd:  notice:  Initiating notify  pgsqld_post_notify_promote_0 on hanode3
crmd:  notice:  Initiating notify  pgsqld_post_notify_promote_0 on hanode2
~~~

Dans les log, nous trouvons aussi les traces de l'élection qui a lieu entre
`hanode2` et `hanode3`:

~~~
attrd: info:Setting lsn_location-pgsqld[hanode2]: (null) -> 21#100672008
attrd: info:Setting lsn_location-pgsqld[hanode3]: (null) -> 21#100672008
[...]
pgsqlms(pgsqld): DEBUG: checking if current node is the best candidate for promotion
pgsqlms(pgsqld): DEBUG: comparing with "hanode3": TL#LSN is 21#100672008
pgsqlms(pgsqld):  INFO: Promote complete
~~~

:::


-----

## Failback du primaire

* suite à un incident sur la ressource ou la perte de son nœud
* même problématique que pour un secondaire
* l'instance doit en plus être reconstruite en secondaire
* le reste de la procédure est similaire au failback d'un secondaire

::: notes

Suite à la perte brutale d'une instance primaire, le cluster bascule le rôle
`Master` sur le meilleur secondaire disponible. Néanmoins, il est possible que
l'ancien primaire possède toujours des données qui n'avaient pas été
répliquées. Dans ces circonstances, il n'est pas recommandé de rattacher
directement l'ancien primaire au nouveau. Il est nécessaire de le
"resynchroniser".

Différentes méthodes sont disponibles mais ne sont pas abordées dans ce
document. Par exemple: `pg_rewind`, restauration _PITR_ ou `pg_basebackup`.

Une fois l'instance resynchronisée, le reste de la procédure est identique à
celle détaillée dans le chapitre [Failback d'un secondaire]:

1. re-synchroniser l'instance sur le nœud
2. positionner `is-managed=false` pour la ressource
3. démarrer le cluster sur le nœud à ré-intégrer
4. démarrer manuellement l'instance sur le nœud
5. valider que cette dernière réplique correctement
6. arrêter l'instance
7. effectuer une commande `refresh` de la ressource
8. supprimer `is-managed=false` pour la ressource

Pour plus de facilité, il est possible d'utiliser ici `systemctl` pour
démarrer et arrêter la ressource. L'important est qu'en fin de procédure,
`systemd` ne voit pas l'instance comme étant démarrée de son point vue,
cette dernière étant gérée non pas par lui mais par Pacemaker.

:::

-----

### TP: Failback du primaire

::: notes

1. re-synchroniser l'instance `hanode1`
2. désactiver la gestion du cluster de `pgsqld-clone`
3. démarrer le cluster sur `hanode1`
4. démarrer manuellement l’instance PostgreSQL sur `hanode1`
5. valider que cette dernière réplique correctement
6. arrêter l’instance sur `hanode1`
7. effectuer une commande `refresh` de `pgsqld`
8. supprimer `is-managed=false` pour la ressource

:::

-----

### Correction: Failback du primaire

::: notes

1. re-synchroniser l'instance `hanode1`

~~~console
# su - postgres
$ rm -r ~postgres/12/data/*
$ /usr/pgsql-12/bin/pg_basebackup -h 10.20.30.5 -D ~postgres/12/data/ -P
$ touch ~postgres/12/data/standby.signal
~~~

NB: le paramètre `primary_conninfo` ou le fichier `pg_hba.conf` n'ont pas à
être corrigés, ces derniers étant positionnés en dehors du `PGDATA`.

2. désactiver la gestion du cluster de `pgsqld-clone`

~~~console
# pcs resource unmanage pgsqld-clone
~~~

3. démarrer le cluster sur `hanode1`

~~~console
# pcs cluster start
~~~

4. démarrer manuellement l’instance PostgreSQL sur `hanode1`

~~~console
# systemctl start postgresql-12
~~~

5. valider que cette dernière réplique correctement

Depuis `hanode2`, la ressource n'est détectée comme démarrée, cette
dernière étant arrêté lors du démarrage du cluster sur `hanode1`. Le nœud
ayant été redémarré, il n'y a pas non plus d'opération `monitor`
récurrente pour `pgsqld` sur `hanode1`.

~~~console
# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld]
     pgsqld	(ocf::heartbeat:pgsqlms):	Master hanode2 (unmanaged)
     pgsqld	(ocf::heartbeat:pgsqlms):	Slave hanode3 (unmanaged)
     Stopped: [ hanode1 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode2
 
# sudo -iu postgres psql
postgres=# select state, application_name
  from pg_stat_replication
  where application_name = 'hanode1';
   state   | application_name 
-----------+------------------
 streaming | hanode1

(1 row)
~~~

6. arrêter l’instance sur `hanode1`

~~~console
# systemctl stop postgresql-12
~~~

Attendre que Pacemaker détecte l'arrêt de l'instance.

7. effectuer une commande `refresh` de `pgsqld`

~~~console
# pcs resource failcount show pgsqld hanode1
Failcounts for resource 'pgsqld' on node 'hanode1'
  hanode1: 2

# pcs resource refresh pgsqld --node=hanode1
Cleaned up pgsqld:0 on hanode1
Cleaned up pgsqld:1 on hanode1
Cleaned up pgsqld:2 on hanode1

  * The configuration prevents the cluster from stopping or starting 'pgsqld-clone' (unmanaged)
Waiting for 3 replies from the CRMd... OK

# pcs resource failcount show pgsqld hanode1
No failcounts for resource 'pgsqld' on node 'hanode1'
~~~

8. supprimer `is-managed=false` pour la ressource

~~~console
# pcs resource manage pgsqld-clone
~~~

:::

-----

## Détails d'un switchover

* opération planifiée
* macro-procédure:
  1. arrêt propre de l'instance primaire
  2. redémarrage de l'instance primaire en secondaire
  3. vérification du secondaire désigné
  4. élection et promotion du secondaire
  
::: notes

Dans le cadre de cette formation, un _switchover_ désigne la promotion
contrôlée d'une instance secondaire et le raccrochage de l'ancien primaire en
tant que secondaire, sans reconstruction.

Le switchover s'appuie sur la procédure standard de PostgreSQL pour effectuer
la bascule.:

* __Rétrograder le primaire__
  
  Cette étape consiste à éteindre l'instance primaire et la redémarrer en tant
  que secondaire. Avant qu'elle ne s'arrête, l'instance primaire envoie tous
  les journaux de transactions nécessaires aux secondaires **connectées**.

  Cette étape est effectuée durant l'opération `demote`.
* __Contrôle du secondaire__
  
  Cette étape consiste à vérifier sur le secondaire que tous les journaux de
  transaction de l'ancien primaire ont bien été reçu, jusqu'au `shutdown
  checkpoint`.
  
  L'agent interrompt la transition en cas d'échec de ces contrôle. Le cluster
  décide alors que faire en fonction des contraintes en place.
  
  Cette étape est réalisée lors de l'opération `notify` exécutée juste
  avant la promotion.
* __Promotion du secondaire__
  
  Exécution de `pg_ctl promote` sur l'instance secondaire. Cette étape est
  réalisée par l'opération `promote`.

Le choix du secondaire à promouvoir dépend de la procédure choisie pour
déplacer le rôle. Il existe deux méthodes pour demander au cluster de
déplacer le rôle `Master` vers un autre nœud.

La première consiste à bannir le rôle `Master` de son emplacement actuel.
Cela implique de positionner une contrainte location `-INFINITY` pour le
rôle `Master` sur son nœud courant. Attention, la contrainte concerne bien
le rôle et non la ressource ! Dans cette situation, le cluster choisi et
promeut alors le clone avec le master score le plus élevé. Cette procédure
se traduit avec les commandes `pcs` suivantes:

~~~
pcs resource ban <resource_name> --master
# ou
pcs resource move <resource_name> --master
~~~

La seconde méthode consiste à imposer l'emplacement du rôle `Master` avec
une contrainte de location `INFINITY` sur un nœud. Cette procédure
se traduit avec la commande `pcs` suivante:

~~~
pcs resource move <resource_name> --master <node_name>
~~~

Dans ces commandes, `<resource_name>` désigne la ressource multi-state et non
le nom des clones.

Dans les deux cas, il faut penser à supprimer ces contraintes après le
switchover avec la commande `pcs resource clear <resource_name>`.
L'utilisation de l'option `resource-stickiness` au niveau du cluster ou des
ressources permet à la ressource de rester sur son nouveau nœud après la
suppression de la contrainte de localisation.

:::

-----

### TP: Switchover

::: notes

1. provoquer une bascule vers le nœud `hanode2`
2. afficher les contraintes pour la ressource `pgsqld-clone`
3. observer les scores au sein du cluster
4. retirer la contrainte positionnée par la bascule
5. observer la transition proposée dans les log du DC
6. répéter les même opérations en effectuant la bascule avec chacune des
   commandes suivantes :

~~~
pcs resource move pgsqld-clone --master
pcs resource ban pgsqld-clone --master
~~~

Pour chacune, observer :

* les contraintes posées par `pcs`
* le statut de la ressource sur le nœud où la contrainte est posée

7. retirer les contraintes des commandes précédentes sur la ressource

:::

-----

### Correction: Switchover

::: notes


1. provoquer une bascule vers le nœud `hanode3`

~~~console
# pcs resource move --master --wait pgsqld-clone hanode3
Resource 'pgsqld-clone' is master on node hanode3; slave on nodes hanode1, hanode2.
~~~

2. afficher les contraintes pour la ressource `pgsqld-clone`

~~~console
# pcs constraint location show resource pgsqld-clone
Location Constraints:
  Resource: pgsqld-clone
    Enabled on: hanode3 (score:INFINITY) (role: Master)
~~~

Une constrainte de localisation avec un poid `INFINITY` a été créée pour le
rôle `Master` de `pgsqld-clone` sur `hanode2`.

3. observer les scores au sein du cluster

~~~console
# crm_simulate -sL|grep 'promotion score'
pgsqld:0 promotion score on hanode3: INFINITY
pgsqld:2 promotion score on hanode1: 1000
pgsqld:1 promotion score on hanode2: 990

~~~

Cette contrainte de localisation influence directement le score de promotion
calculé.

4. retirer la contrainte positionnée par la bascule

~~~console
# pcs resource clear pgsqld-clone

# crm_simulate -sL|grep "promotion score"
pgsqld:0 promotion score on hanode3: 1003
pgsqld:2 promotion score on hanode1: 1000
pgsqld:1 promotion score on hanode2: 990

# pcs constraint location show resource pgsqld-clone
Location Constraints:
~~~

La situation revient à la normale et l'instance principale reste à son
nouvel emplacement.

5. observer la transition proposée dans les log du DC

~~~
pengine:  debug: Allocating up to 3 pgsqld-clone instances to a possible 3 nodes (at most 1 per host, 1 optimal)
pengine:  debug: Assigning hanode1 to pgsqld:1
pengine:  debug: Assigning hanode2 to pgsqld:2
pengine:  debug: Assigning hanode3 to pgsqld:0
pengine:  debug: Allocated 3 pgsqld-clone instances of a possible 3
pengine:  debug: pgsqld:0 master score: 1000000
pengine:   info: Promoting pgsqld:0 (Slave hanode3)
pengine:  debug: pgsqld:1 master score: 1001
pengine:  debug: pgsqld:2 master score: 990
pengine:   info: pgsqld-clone: Promoted 1 instances of a possible 1 to master
pengine:  debug: Assigning hanode3 to pgsql-master-ip
pengine:   info: Start recurring monitor (15s) for pgsqld:0 on hanode3
pengine:   info: Cancelling action pgsqld:0_monitor_16000 (Slave vs. Master)
pengine:   info: Cancelling action pgsqld:1_monitor_15000 (Master vs. Slave)
pengine:   info: Start recurring monitor (16s) for pgsqld:1 on hanode1
pengine:   info: Start recurring monitor (15s) for pgsqld:0 on hanode3
pengine:   info: Start recurring monitor (16s) for pgsqld:1 on hanode2
pengine:   info: Start recurring monitor (10s) for pgsql-master-ip on hanode3
pengine:   info:   Leave   fence_vm_hanode1  (Started hanode2)
pengine:   info:   Leave   fence_vm_hanode2  (Started hanode1)
pengine:   info:   Leave   fence_vm_hanode3  (Started hanode1)
pengine: notice: * Promote pgsqld:0          (Slave -> Master hanode3)
pengine: notice: * Demote  pgsqld:1          (Master -> Slave hanode2)
pengine:   info:   Leave   pgsqld:2          (Slave hanode1          )
pengine: notice: * Move    pgsql-master-ip   (hanode2 -> hanode3     )
~~~

6. répéter les même opérations en effectuant la bascule avec chacune des
   commandes suivantes :

~~~
pcs resource move pgsqld-clone --master
pcs resource ban pgsqld-clone --master
~~~

Ces deux commandes sont similaires. Dans les deux cas, une contrainte de
localisation avec un score `-INFINITY` est positionnée pour le rôle `Master`
sur le nœud l'hébergeant.

~~~console
# pcs resource ban --master --wait pgsqld-clone
Warning: Creating location constraint cli-ban-pgsqld-clone-on-hanode1 with a score of -INFINITY for resource pgsqld-clone on node hanode1.
This will prevent pgsqld-clone from being promoted on hanode1 until the constraint is removed. This will be the case even if hanode1 is the last node in the cluster.
Resource 'pgsqld-clone' is master on node hanode2; slave on nodes hanode1, hanode3.

# pcs constraint location show resource pgsqld-clone
Location Constraints:
  Resource: pgsqld-clone
    Disabled on: hanode1 (score:-INFINITY) (role: Master)


# crm_simulate -sL|grep "promotion score"
pgsqld:1 promotion score on hanode1: 1001
pgsqld:2 promotion score on hanode3: 990
pgsqld:0 promotion score on hanode2: -INFINITY
~~~

7. retirer les contraintes des commandes précédentes sur la ressource

~~~console
# pcs resource clear pgsqld-clone
# crm_simulate -sL|grep "promotion score"
pgsqld:2 promotion score on hanode1: 1001
pgsqld:1 promotion score on hanode2: 1000
pgsqld:0 promotion score on hanode3: 990
~~~

:::

-----

# Supervision

Ce chapitre aborde les différents axes de supervision d'un cluster Pacemaker.

-----

## Sondes

* supervision basique avec `crm_mon`
* état du cluster avec `check_crm` (on pourrait ne pas remarquer les bascules!)
  * [check_crm](https://exchange.nagios.org/directory/Plugins/Clustering-and-High-2DAvailability/Check-CRM/details)
* état des __rings__ corosync avec `check_corosync_rings`
  * [check_corosync_rings](https://exchange.nagios.org/directory/Plugins/Clustering-and-High-2DAvailability/Check-Corosync-Rings/details)

::: notes

Il existe peu de projet permettant d'intégrer la supervision d'un cluster
Pacemaker au sein d'un système centralisé, eg. Nagios ou dérivés. Nous pouvons
citer `crm_mon`, `check_crm` ou `check_corosync_rings`.

**crm\_mon**

L'outil `crm_mon` est capable de produire une sortie adaptée à Nagios grâce
à l'argument `--simple-status`. Néanmoins, la remontée d'erreur est limitée
à la seule disponibilité des nœuds, mais pas des ressources.

Voici un exemple avec le cluster dans son état normal:

~~~console
# crm_mon --simple-status
CLUSTER OK: 3 nodes online, 7 resources configured
~~~

L'outil ne rapporte pas d'erreur en cas d'incident sur une ressource:

~~~console
# killall postgres

# pcs resource show
 Master/Slave Set: pgsqld-clone [pgsqld]
     pgsqld	(ocf::heartbeat:pgsqlms):	FAILED hanode1
     Masters: [ hanode2 ]
     Slaves: [ hanode3 ]
 pgsql-master-ip	(ocf::heartbeat:IPaddr2):	Started hanode2

# crm_mon --simple-status
CLUSTER OK: 3 nodes online, 7 resources configured
~~~

Mais remonte une erreur en cas de perte d'un nœud:

~~~console
# pcs stonith fence hanode3
Node: hanode3 fenced

# crm_mon --simple-status
CLUSTER WARN: offline node: hanode3
~~~

Cette sonde est donc peu utile, car souvent en doublon avec une sonde
pré-existante confirmant que le serveur est bien démarré. Elle peut
éventuellement servir à confirmer que les services Pacemaker/Corosync sont
bien démarrés sur chaque nœud du cluster.


**check\_crm**

Malheureusement, l'outil n'a pas été mis à jour depuis 2013. Il dépend du
paquet `libmonitoring-plugin-perl` sous Debian et dérivés et de `epel-release` et
`perl-Monitoring-Plugin.noarch` sous les RedHat et dérivés.

Le module perl ayant changé de nom depuis, il est nécessaire de modifier deux
lignes dans le code source:

~~~console
sed -i 's/Nagios::Plugin/Monitoring::Plugin/' check_crm.pl
~~~

Ci-dessous, le cas d'une ressource ayant subit au moins une erreur. L'option -f
permet d'indiquer le nombre minimal d'erreur avant que la sonde ne lève une
alerte:

~~~console
# ./check_crm.pl
check_crm WARNING - : pgsqld failure detected, fail-count=1

# ./check_crm.pl -f 3
check_crm OK - Cluster OK

# pcs resource failcount reset pgsqld
[...]

# ./check_crm.pl
check_crm OK - Cluster OK
~~~

L'argument `-c` de la sonde permet de lever une alerte si une
contrainte existe sur une ressource suite à un déplacement forcé
(eg. `crm_resource --ban`). Malheureusement, cette commande dépend de `crmsh`
et ne fonctionne donc pas avec `pcs`.


**check\_corosync\_rings**

L'outil **check\_corosync\_rings** permet de détecter les incidents réseau
au niveau Corosync. Par exemple, voici le cas d'un anneau défaillant :

~~~console
# ifdown eth1
Device 'eth1' successfully disconnected.

# ./check_corosync_ring.pl
check_cororings CRITICAL - Running corosync-cfgtool failed

# corosync-cfgtool -s
Printing ring status.
Local node ID 1
RING ID 0
  id  = 192.168.122.2
  status  = ring 0 active with no faults
RING ID 1
  id  = 192.168.100.2
  status  = Marking ringid 1 interface 192.168.100.2 FAULTY*

# ifup eth1
Connection successfully activated (D-Bus active path: /org/freedesktop/NetworkManager/ActiveConnection/3)

# corosync-cfgtool -s
Printing ring status.
Local node ID 1
RING ID 0
  id  = 192.168.122.2
  status  = ring 0 active with no faults
RING ID 1
  id  = 192.168.100.2
  status  = ring 1 active with no faults

# ./check_corosync_ring.pl 
check_cororings OK - ring 0 OK ring 1 OK
~~~

:::

-----

## Alertes Pacemaker

* Déclenche une action en cas d'évènement
* Possibilité d'exécuter un script
* Exemples fournis : écriture dans un fichier de log, envoi de mail, envoi trap SNMP
* Disponible depuis Pacemaker 1.1.15

::: notes

Depuis la version 1.1.15, Pacemaker offre la possibilité de lancer des
[alertes](https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/1.1/html/Pacemaker_Explained/ch07.html)
en fonction de certains évènements: nœud défaillant, ressource qui démarre
ou s'arrête, etc.

Le principe est assez simple, Pacemaker lance un script et lui transmet des
variables d'environnement, un _timestamp_ et des destinataires (`recipient`).
Cela laisse une grande liberté dans l'écriture de script.

Pacemaker propose plusieurs scripts en exemple stockés dans
`/usr/share/pacemaker/alerts` :

  * `alert_file.sh.sample` : écriture de l'évènement dans un fichier texte
  * `alert_smtp.sh.sample` : envoi d'un mail
  * `alert_snmp.sh.sample` : envoi d'une "trap" snmp

Voici un exemple de configuration avec `alert_file.sh.sample` :

~~~xml
<configuration>
  <alerts>
    <alert id="alert_sample" path="/usr/share/pacemaker/alerts/alert_file.sh.sample">
      <meta_attributes id="config_for_timestamp">
        <nvpair id="ts_fmt" name="timestamp-format" value="%H:%M:%S.%06N"/>
      </meta_attributes>
      <recipient id="logfile_destination" value="/var/log/alerts.log"/>
    </alert>
  </alerts>
</configuration>
~~~

Dans cet exemple, Pacemaker exécutera le script
`/usr/share/pacemaker/alerts/alert_file.sh` et lui transmet :

  * `timestamp-format` : format du timestamp
  * `logfile_destination` : défini comme un `recipient`, emplacement du fichier de destination

Le script est appelé autant de fois que de `recipient` définis.

Ci-après comment une telle alerte peut être déployée en utilisant les outils
classiques. Bien entendu, une méthode plus intégrée et simple est proposée
par l'outil `pcs`.

~~~
cp /usr/share/pacemaker/alerts/alert_file.sh.sample /usr/share/pacemaker/alerts/alert_file.sh
chmod +x /usr/share/pacemaker/alerts/alert_file.sh
touch /var/log/cluster/alerts.log
chown hacluster:haclient /var/log/cluster/alerts.log
crm_shadow --create alert
cat <<EOF > alert.xml
<configuration>
  <alerts>
    <alert id="alert_sample" path="/usr/share/pacemaker/alerts/alert_file.sh">
      <meta_attributes id="config_for_timestamp">
        <nvpair id="ts_fmt" name="timestamp-format" value="%H:%M:%S.%06N"/>
      </meta_attributes>
      <recipient id="logfile_destination" value="/var/log/cluster/alerts.log"/>
    </alert>
  </alerts>
</configuration>
EOF
cibadmin --modify --xml-file alert.xml
crm_shadow -d
crm_shadow -f --commit alert
~~~

Dans les logs :

~~~
info: parse_notifications: We have an alerts section in the cib
Found alert: id=alert_sample, path=[...]/alert_file.sh, timeout=30000, tstamp_format=%H:%M:%S.%06N
Alert has recipient: id=logfile_destination, value=/var/log/cluster/alerts.log
~~~

Suite à un changement dans le cluster, nous observons dans le fichier
`alerts.log` par exemple:

~~~
11:47:24.397811: Resource operation 'notify' for 'pgsqld' on 'hanode2': ok
11:47:25.408174: Resource operation 'demote' for 'pgsqld' on 'hanode2': ok
11:47:26.032790: Resource operation 'notify' for 'pgsqld' on 'hanode2': ok
11:47:26.549325: Resource operation 'stop' for 'pgsql-master-ip' on 'hanode2': ok
11:47:26.789720: Resource operation 'notify' for 'pgsqld' on 'hanode2': ok
11:47:27.341088: Resource operation 'stop' for 'pgsqld' on 'hanode2': ok
~~~

Il pourrait être intéressant d'adapter ce script pour utiliser l'outil
`logger` au lieu d'écrire directement dans un fichier. Ces modifications sont
laissés à l'exercice du lecteur.

:::

-----

### TP: Alertes Pacemaker

::: notes

1. installer `alert_file.sh.sample` dans `/var/lib/pacemaker/alert_file.sh` et
   positionner son propriétaire et le droit d'exécution dessus.
2. créer le fichier de log `/var/log/cluster/pcmk_alert.log`
3. attribuer à ce fichier les mêmes droits et propriétaire que
   `/var/log/cluster/corosync.log`
4. créer une configuration `logrotate` pour ce fichier de log
5. ajouter une alerte utilisant `alert_file.sh` avec `pcs`.
   préciser le format de la date.
6. ajouter `/var/log/cluster/pcmk_alert.log` comme destinataire de l'alerte
7. vérifier avec `pcs` l'existence de votre alerte
8. provoquer une bascule de `pgsqld-clone`
9. comparer les log sur les trois nœuds

:::

-----

### Correction: Alertes Pacemaker

::: notes

1. installer `alert_file.sh.sample` dans `/var/lib/pacemaker/alert_file.sh` et
   positionner son propriétaire et le droit d'exécution dessus.

Sur les trois nœuds du cluster:

~~~console
# install --owner=hacluster --group=haclient --mode=0755 \
    /usr/share/pacemaker/alerts/alert_file.sh.sample     \
    /var/lib/pacemaker/alert_file.sh
~~~

2. créer le fichier de log `/var/log/cluster/pcmk_alert.log`

Sur les trois nœuds du cluster:

~~~console
# touch /var/log/cluster/pcmk_alert.log
~~~

3. attribuer à ce fichier les mêmes droits et propriétaire que
   `/var/log/cluster/corosync.log`

Sur les trois nœuds du cluster:

~~~console
# chown hacluster:haclient /var/log/cluster/pcmk_alert.log
# chmod 0660 /var/log/cluster/pcmk_alert.log
~~~

4. créer une configuration `logrotate` pour ce fichier de log

Sur les trois nœuds du cluster:

~~~console
# cat <<'EOF' > /etc/logrotate.d/pcmk_alert
/var/log/cluster/pcmk_alert.log {
  missingok
  compress
  copytruncate
  daily
  rotate 31
  minsize 2048
  notifempty
}
EOF
~~~

5. ajouter une alerte utilisant `alert_file.sh` avec `pcs`

~~~console
# pcs alert create id=alert_file          \
    description="Log events to a file."   \
    path=/var/lib/pacemaker/alert_file.sh \
    meta timestamp-format="%Y-%m-%d %H:%M:%S.%03N"
~~~

6. ajouter `/var/log/cluster/pcmk_alert.log` comme destinataire de l'alerte

~~~console
# pcs alert recipient add alert_file id=my-alert_logfile \
    value=/var/log/cluster/pcmk_alert.log
~~~

7. vérifier avec `pcs` l'existence de votre alerte

~~~console
# pcs alert show
Alerts:
 Alert: alert_file (path=/var/lib/pacemaker/alert_file.sh)
  Description: Log events to a file.
  Recipients:
   Recipient: my-alert_logfile (value=/var/log/cluster/pcmk_alert.log)
~~~

8. provoquer une bascule de `pgsqld-clone`

~~~console
# pcs resource move --master --wait pgsqld-clone hanode2
# pcs resource clear pgsqld-clone
~~~

9. comparer les log sur les trois nœuds

L'instance primary était sur `hanode1`. Nous trouvons dans ses log les
opérations nécessaires pour déplacer le rôle `Master` ailleurs:

~~~
# cat /var/log/cluster/pcmk_alert.log
16:09:40.796250: Resource operation 'notify' for 'pgsqld' on 'hanode1': ok
16:09:41.437972: Resource operation 'demote' for 'pgsqld' on 'hanode1': ok
16:09:41.666059: Resource operation 'notify' for 'pgsqld' on 'hanode1': ok
16:09:42.159610: Resource operation 'stop' for 'pgsql-master-ip' on 'hanode1': ok
16:09:42.415470: Resource operation 'notify' for 'pgsqld' on 'hanode1': ok
16:09:43.396618: Resource operation 'notify' for 'pgsqld' on 'hanode1': ok
16:09:43.611377: Resource operation 'monitor (16000)' for 'pgsqld' on 'hanode1': ok
~~~

L'instance cible était sur `hanode2`, nous trouvons dans ses log les
opérations nécessaires à sa promotion:

~~~
# cat /var/log/cluster/pcmk_alert.log
16:09:40.781285: Resource operation 'notify' for 'pgsqld' on 'hanode2': ok
16:09:41.583250: Resource operation 'notify' for 'pgsqld' on 'hanode2': ok
16:09:42.364046: Resource operation 'notify' for 'pgsqld' on 'hanode2': ok
16:09:42.909637: Resource operation 'promote' for 'pgsqld' on 'hanode2': ok
16:09:43.286059: Resource operation 'notify' for 'pgsqld' on 'hanode2': ok
16:09:43.753243: Resource operation 'start' for 'pgsql-master-ip' on 'hanode2': ok
16:09:44.013828: Resource operation 'monitor (10000)' for 'pgsql-master-ip' on 'hanode2': ok
16:09:44.135493: Resource operation 'monitor (15000)' for 'pgsqld' on 'hanode2': master (target: 8)
~~~

Enfin, nous ne trouvons sur `hanode3` que les opérations de notification:

~~~
# cat /var/log/cluster/pcmk_alert.log
16:09:40.824536: Resource operation 'notify' for 'pgsqld' on 'hanode3': ok
16:09:41.654399: Resource operation 'notify' for 'pgsqld' on 'hanode3': ok
16:09:42.201205: Resource operation 'notify' for 'pgsqld' on 'hanode3': ok
16:09:43.413522: Resource operation 'notify' for 'pgsqld' on 'hanode3': ok
~~~

:::

