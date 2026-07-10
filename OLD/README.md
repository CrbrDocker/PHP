#* Redis

## Build
Note : depend de buildx (cross platform build) & la VM de base Debian Bookworm.

*** Les fichiers
- DockerFileXXX : le dockerfile... pour lancer le build
- install-truc.sh : fichier d'install de l'image. Il est copie et execute dans l'image pendant le build
- ./need_rebuild.sh : script qui permet de checker les modification et rebuilder au cas ou, si il y a eu des modifications ou des packages à updater. possiblement automatisable periodiquement.

### Build : 

#### Build de test : 
```
docker build --no-cache -f DockerFileXXXX -t monimagedetest .
```
... et ensuite, on peut la run

PS : penser a  tout cleaner prune & co avant de lancer le build final.


#### Build final, pushed sur le repo : 
```
docker buildx build --no-cache --platform linux/amd64,linux/arm64 -f DockerFileXXXX -t REPO/XXX . --push
```
Attention, il faut le lancer imperativement dans le repertoire ici, sinon des problemes de path
(note, on doit le pusher avec buildx directement, sinon ca ne met pas l'image a dispo, ca la laisse juste dans le cache de build) 

#### Automatisation build : 
le script ./need_rebuild.sh peut tout faire. Il faut le lancer imperativement dans le repertoire ici, sinon des problemes de path

## Utilisation
Juste docker run ... 

Image Basee du Debian Bookworm
L'image a ma config standard toutes les limites et nombre de process a spawn en version "dev" donc low.
TODO : des variables d'env pour overrider toute la conf.

2 Vhosts sont crees :
 * un vhost par default : /srv/www/default/public
 * vhost_alias qui permet de creer des vhosts a la volee
Un certificat SSL pour tous les vhosts_alias signe par notre autorite est installe de base.

Au besoin, overrider /srv/www et /etc/apache2/sites-enabled.
