#!/bin/bash

usage()
{
cat << EOF

usage: $0 options

###################
#### PPA tests ####
###################


OPTIONS:
   -h      Help info
   -n      Build from scratch - remove local cache
   -p      Ubuntu PPA Launchpad repository to use for Suricata package testing
   -u      Only do the run with this specific Ubuntu - aka "-u latest"
   -i      Include i386 builds
           
  This script is for the purpose of doing a Suricata package testing from the Ubuntu PPA Launchpad repositories located here -
  https://launchpad.net/~oisf
  
  The repositories used to test the Suricata (packages) are - stable, beta, daily,ids-ips(test). Based on those - 
  the relevant dockers have been build and tagged here - https://hub.docker.com/r/pevma/sqard/tags/
  
  NOTE: If you would like to run and build all docker containers from scratch and do not use anything 
  cached on the system 
  
   EXAMPLE: 
   ./duppalt.sh -p ppatest
   The example above will initiate tests with all dockers that contain "ppatest" in their tag name.
   
   ./duppalt.sh -p ppadaily
   The example above will initiate tests with all dockers that contain "ppadaily" in their tag name.
   
   ./duppalt.sh -p ppastable
   The example above will initiate tests with all dockers that contain "ppastable" in their tag name.
   
   ./duppalt.sh -p ppabeta
   The example above will initiate tests with all dockers that contain "ppabeta" in their tag name.
   
    ./duppalt.sh -u devel
   The example above will initiate tests with Ubuntu devel only. Note: the default PPA 
   (if not otherwise specified with the "-p" option) is ppatest.

EOF
}

# set up Ubuntu releases
ubuntu_releases=(devel rolling xenial trusty)

ppa="ppatest"
#default is the test repo unless otherwise specified
nochache=

while getopts “hnp:u:i” OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         n)
             nocache="yes"
             #build dockers from scratch - use nocache
             ;;
         p)
             ppa=$OPTARG
             if [[ ! ${ppa} =~ ^(ppastable|ppabeta|ppadaily|ppatest)$ ]]; 
             then
               echo -e "\n Please check the option's spelling \n"
               echo -e "Only - ppastable, ppabeta, ppadaily, ppatest are allowed\n"
               usage
               exit 1;
             fi
             ;;
         u)
             single_ubuntu=$OPTARG
             if [[ "$single_ubuntu" =~ ^(rolling|trusty|devel|xenial)$ ]];
             then
               echo -e "\n Using single Ubuntu release set to ${single_ubuntu} \n"
               ubuntu_releases=("${single_ubuntu}")
             else
               echo -e "\n Please check the option's spelling "
               echo -e " Only - ${ubuntu_releases[@]} are allowed !! \n"
               usage
               exit 1;
             fi
             ;;
         i)
             i386="yes"
             ;;
         *)
             usage
             ;;
     esac
done
shift $((OPTIND -1))

for release in ${ubuntu_releases[@]}
do
docker_containers+=("ubuntu-${release}-${ppa}")
echo "ubuntu-${release}-${ppa}"

if [ ${i386} ];
then
    docker_containers+=("ubuntu-i386-${release}-${ppa}")
    echo "ubuntu-i386-${release}-${ppa}"
fi

done

if [ ${nocache} ];
then
    for i in $(docker images -a |grep ${ppa} | awk '{print $3}')
        do
        #docker rm $i
        docker rmi $i
    done

fi

time=$(date +%Y-%m-%d-%H-%M)
log_file=$(echo ${ppa}-RESULTS-${time}.log)
echo > ${log_file}

for container in "${docker_containers[@]}"
do
  echo "Using CONTAINER: -> ${container}" |tee -a >> ${log_file}
done

# fire em up
for container in "${docker_containers[@]}"
do
  docker pull pevma/sqard:${container}
  docker run --name sqard-${container} -d -ti pevma/sqard:${container} 
done

for container in "${docker_containers[@]}"
do
  echo "=====================${container}====================="  >> ${log_file}
  echo -e "\nInitial state - sqard-${container}\n"                      >> ${log_file}
  
  echo -e "\nsqard command: dpkg -l |grep suricata \n" >> ${log_file}
  docker exec sqard-${container} dpkg -l |grep suricata \
  &>> ${log_file}
  
  echo -e "\nsqard command: dpkg -l |grep htp  \n" >> ${log_file}
  docker exec sqard-${container} dpkg -l |grep htp \
  &>> ${log_file}
  
  echo -e "\nsqard command: ps aux |grep suricata \n" >> ${log_file}
  docker exec sqard-${container} ps aux |grep suricata \
  &>> ${log_file}
  
  echo -e "\nsqard command: suricata --build-info \n" >> ${log_file}
  docker exec sqard-${container} suricata --build-info \
  &>> ${log_file}
  
  echo -e "\nsqard command: ldd /usr/bin/suricata \n" >> ${log_file}
  docker exec sqard-${container} ldd /usr/bin/suricata \
  &>> ${log_file}
  
  echo -e "\nTest upgrade if available - sqard-${container}\n" \
  >> ${log_file}
  
  docker exec sqard-${container} sh -c \
  'DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade suricata'
  
  echo -e "\nsqard command: service suricata stop \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'service suricata stop'
  
  sleep 10
  
  # make sure we clean up for sure just in case
  echo -e "\nsqard command: rm -rf /var/run/suricata.pid \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'rm -rf /var/run/suricata.pid'
  
  echo -e "\nsqard command: rm -rf /var/log/suricata/suricata.log \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'rm -rf /var/log/suricata/suricata.log' \
  &>> ${log_file}
  
  echo -e "\nsqard command: service suricata start \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'service suricata start'
  
  sleep 30
  
  echo -e "\nsqard command: dpkg -l |grep suricata \n" >> ${log_file}
  docker exec sqard-${container} dpkg -l |grep suricata \
  &>> ${log_file}
  
  echo -e "\nsqard command: dpkg -l |grep htp \n" >> ${log_file}
  docker exec sqard-${container} dpkg -l |grep htp \
  &>> ${log_file}
  
  echo -e "\nsqard command: ps aux |grep suricata \n" >> ${log_file}
  docker exec sqard-${container} ps aux |grep suricata \
  &>> ${log_file}
  
  echo -e "\nsqard command: suricata --build-info \n" >> ${log_file}
  docker exec sqard-${container} suricata --build-info \
  &>> ${log_file}
  
  echo -e "\nsqard command: ldd /usr/bin/suricata \n" >> ${log_file}
  docker exec sqard-${container} ldd /usr/bin/suricata \
  &>> ${log_file}
  
  echo -e "\nBegin test sequence  sqard-${container}\n" \
  &>> ${log_file}
  
  echo -e "\nsqard command: wget -O /var/cache/testmyids.txt www.testmyids.com/ \n" >> ${log_file}
  docker exec sqard-${container} wget -O /var/cache/testmyids.txt www.testmyids.com/ \
  &>> ${log_file}
  
  echo -e "\nsqard command: ls -lh /var/log/suricata/ \n" >> ${log_file}
  docker exec sqard-${container} ls -lh /var/log/suricata/ \
  &>> ${log_file}
  
  echo -e "\nsqard command: cat /var/log/suricata/fast.log \n" >> ${log_file}
  docker exec sqard-${container} cat /var/log/suricata/fast.log \
  &>> ${log_file}
  
  echo -e "\nsqard command: grep '\"event_type\":\"alert\"' /var/log/suricata/eve.json |grep testmyids | jq . \n" >> ${log_file}
  docker exec sqard-${container} grep '"event_type":"alert"' /var/log/suricata/eve.json |grep testmyids | jq . \
  &>> ${log_file}
  
  echo -e "\nsqard command: grep '\"event_type\":\"http\"' /var/log/suricata/eve.json  |grep testmyids | jq . \n" >> ${log_file}
  docker exec sqard-${container} grep '"event_type":"http"' /var/log/suricata/eve.json  |grep testmyids | jq . \
  &>> ${log_file}
  
  echo -e "\nsqard command: grep '\"event_type\":\"fileinfo\"' /var/log/suricata/eve.json  |grep testmyids | jq . \n" >> ${log_file}
  docker exec sqard-${container} grep '"event_type":"fileinfo"' /var/log/suricata/eve.json  |grep testmyids | jq . \
  &>> ${log_file}
  
  echo -e "\nsqard command: grep '\"event_type\":\"dns\"' /var/log/suricata/eve.json  |grep testmyids | jq . \n" >> ${log_file}
  docker exec sqard-${container} grep '"event_type":"dns"' /var/log/suricata/eve.json  |grep testmyids | jq . \
  &>> ${log_file}
  
  echo -e "\nsqard command: cat /var/log/suricata/suricata.log \n" >> ${log_file}
  docker exec sqard-${container} cat /var/log/suricata/suricata.log \
  &>> ${log_file}
  
  echo -e "\nsqard command: service suricata restart \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'service suricata restart'
  
  echo -e "\nSECOND STAGE\n" \
  &>> ${log_file}
  
  sleep 40
  
  echo -e "\nsqard command: suricatasc -c \"uptime\" \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricatasc -c "uptime"' \
  &>> ${log_file}
  
  echo -e "\nsqard command: suricatasc -c \"version\" \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricatasc -c "version"' \
  &>> ${log_file}
  
  echo -e "\nsqard command: suricatasc -c \"capture-mode\" \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricatasc -c "capture-mode"' \
  &>> ${log_file}
  
  echo -e "\nsqard command: suricatasc -c \"running-mode\" \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricatasc -c "running-mode"'\
  &>> ${log_file}
  
  echo -e "\nsqard command: suricatactl filestore prune -h \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricatactl filestore prune -h' \
  &>> ${log_file}

  echo -e "\nsqard command: suricata-update -h \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricata-update -h' \
  &>> ${log_file}
  
  echo -e "\nsqard command: suricata-update update-sources \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricata-update update-sources' \
  &>> ${log_file}
  
  echo -e "\nsqard command: suricata-update enable-source oisf/trafficid \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricata-update enable-source oisf/trafficid' \
  &>> ${log_file}

  echo -e "\nsqard command: suricata-update enable-source ptresearch/attackdetection \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricata-update enable-source ptresearch/attackdetection' \
  &>> ${log_file}
  
  echo -e "\nsqard command: suricata-update list-sources \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricata-update list-sources' \
  &>> ${log_file}
  
  echo -e "\nsqard command: suricata-update list-enabled-sources \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricata-update list-enabled-sources' \
  &>> ${log_file}

  echo -e "\nsqard command: suricata-update \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricata-update' \
  &>> ${log_file}
  
  echo -e "\nsqard command: suricatasc -c \"reload-rules\" \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'suricatasc -c "reload-rules"' \
  &>> ${log_file}
  
  sleep 25
  
  echo -e "\nsqard command: cat /var/log/suricata/suricata.log \n" >> ${log_file}
  docker exec sqard-${container} cat /var/log/suricata/suricata.log \
  &>> ${log_file}
  
  echo -e "\nsqard command: dpkg --status suricata \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'dpkg --status suricata' \
  &>> ${log_file}
  
  echo -e "\nsqard command: man suricata |cat \n" >> ${log_file}
  docker exec sqard-${container} sh -c 'man suricata |cat' \
  &>> ${log_file}
  
  echo -e "=====================${container}=====================\n" >> ${log_file}
  
  # stop and remove containers 
  echo -e "\nStopping container:"
  docker stop sqard-${container}
  
  echo -e "\nRemoving container:"
  docker rm sqard-${container}

done
