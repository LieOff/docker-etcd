#!/bin/bash
if [[ "${1:0:1}" != '-' && "x$1" != "x/bin/etcd" ]]; then
  exec $@
fi

echo -n "$(date +%F\ %T) I | Running "
/bin/etcd --version

INITIAL_CLUSTER_TOKEN=etcd-cluster
NODE_NAME=default
# lock file to make sure we're not running multiple containers on the same volume
LOCK_FILE=/data/ctr.lck

ARGS="--data-dir=/data"
RESTOREARGS="--data-dir=/data-restore"
echo "$@" | grep -q -- "-auto-compaction-retention"
if [[ $? -ne 0 ]]; then
  echo "setting default auto compaction retention"
  ARGS="$ARGS --auto-compaction-retention=1"
fi
echo "$@" | grep -q -- "-listen-peers-urls"
if [[ $? -ne 0 ]]; then
  echo "setting default urls for peers"
  ARGS="$ARGS --listen-peer-urls=http://0.0.0.0:7001,http://0.0.0.0:2380"
fi
echo "$@" | grep -q -- "-listen-client-urls"
if [[ $? -ne 0 ]]; then
  echo "setting default urls for client"
  ARGS="$ARGS --listen-client-urls=http://0.0.0.0:4001,http://0.0.0.0:2379"
fi
echo "$@" | grep -q -- "-initial-advertise-peer-urls"
if [[ $? -ne 0 ]]; then
  echo "setting initial advertise peer urls and initial cluster"
  SECONDS=0
  echo "resolving the container IP with Docker DNS..."
  while [ -z "$cip" ]; do 
    cip=$(dig +short $(hostname))
    # checking that the returned IP is really an IP
    echo "$cip" | egrep -qe "^[0-9\.]+$"
    if [ -z "$cip" ]; then
      sleep 1
    fi
    [[ $SECONDS -gt 10 ]] && break
  done
  echo "$cip" | egrep -qe "^[0-9\.]+$"
  if [ $? -ne 0 ]; then
    # if not resolved by Docker dns, there should be an entry in /etc/hosts
    echo "warning: unable to resolve this container's IP ($cip), checking rancher metadata-service"
    cip=$(curl -s http://rancher-metadata/2015-12-19/self/container/primary_ip)
    echo "Response is: $cip"
  else
    echo "resolved IP: $cip"
  fi
  echo "$cip" | egrep -qe "^[0-9\.]+$"
  if [ $? -ne 0 ]; then
    # if not resolved by Docker dns, there should be an entry in /etc/hosts
    echo "warning: unable to resolve this container's IP ($cip), switching back to /etc/hosts"
    cip=$(grep $(hostname) /etc/hosts |awk '{print $1}' | head -1)
    echo "found IP in /etc/hosts: $cip"
  else
    echo "resolved IP: $cip"
  fi
  echo "$cip" | egrep -qe "^[0-9\.]+$"
  if [ $? -ne 0 ]; then
    echo "error: unable to get this container's IP ($cip)"
    exit 1
  fi
  if [[ -n "$SERVICE_NAME" ]]; then
    INITIAL_CLUSTER_TOKEN=$SERVICE_NAME
    echo "building a seeds list for cluster $SERVICE_NAME"
    # IP of the service tasks
    typeset -i nbt
    nbt=0
    SECONDS=0
    echo "waiting for the min seeds count ($MIN_SEEDS_COUNT)"
    while [[ $nbt -lt ${MIN_SEEDS_COUNT} ]]; do
      tips=$(dig +short $SERVICE_NAME)
      nbt=$(echo $tips | wc -w)
      echo $tips
      [[ $SECONDS -gt 30 ]] && break
    done
    if [[ $nbt -lt ${MIN_SEEDS_COUNT} ]]; then
      echo "error: couldn't reach the min seeds count after $SECONDS sec, only $nbt tasks were found"
      while [[ $nbt -lt ${MIN_SEEDS_COUNT} ]]; do
        conts=$(curl -s rancher-metadata/latest/self/service/containers | cut -d = -f 2)
        nbt=$(echo $conts | wc -w)
        echo $conts
        [[ $SECONDS -gt 30 ]] && break
      done
      if [[ $nbt -lt ${MIN_SEEDS_COUNT} ]]; then
        echo "error: couldn't reach the min seeds count after $SECONDS sec, only $nbt tasks were found"
      else
        tips=""
        for cont in $conts; do
          ip=$(curl -s rancher-metadata/latest/containers/$cont/primary_ip)
          tips="$tips $ip"
          echo "Found $ip in rancher"
        done
      fi
    else
      echo "$nbt seeds found"
    fi
    for tip in $tips; do
      name="${SERVICE_NAME}-${tip##*.}"
      [[ -z "$INITIAL_CLUSTER" ]] && INITIAL_CLUSTER="$name=http://$tip:2380" || INITIAL_CLUSTER="$INITIAL_CLUSTER,$name=http://$tip:2380"
      echo "-----------grep----------------------"
      echo $(grep $(hostname) /etc/hosts |awk '{print $1}' | head -1)
      echo "--------------catEtc/Hosts------------------"      
      cat /etc/hosts
      echo "--------------hostname------------------"      
      echo $(grep $(hostname))
      echo "--------------cip------------------"
      echo "$cip"
      echo "--------------tip------------------"
      echo "$tip"
      echo "----------------endTip-----------------"  
      echo "--------------dig------------------"
      echo $(dig +short $SERVICE_NAME)
      echo "-------------endDig----------------"      
      if [[ "$cip" = "$tip" ]]; then
        NODE_NAME=$name
      fi
    done
  else
      INITIAL_CLUSTER="default=http://$cip:2380"
  fi
  echo "initial cluster is $INITIAL_CLUSTER"
  if [[ -f "/backup/.force-restore" ]]; then
    echo "Forcing restore of data from /backup/snapshot.db"
  fi
  if [[ -f "/backup/.force-restore" ]]; then
    ARGS="$ARGS --name $NODE_NAME --initial-advertise-peer-urls http://$cip:2380 --initial-cluster $INITIAL_CLUSTER --initial-cluster-token $INITIAL_CLUSTER_TOKEN --initial-cluster-state new"
  else
    ARGS="$ARGS --name $NODE_NAME --initial-advertise-peer-urls http://$cip:2380 --initial-cluster $INITIAL_CLUSTER --initial-cluster-token $INITIAL_CLUSTER_TOKEN --initial-cluster-state $INITIAL_CLUSTER_STATE"  
  fi
  RESTOREARGS="$RESTOREARGS --name $NODE_NAME --initial-advertise-peer-urls http://$cip:2380 --initial-cluster $INITIAL_CLUSTER --initial-cluster-token $INITIAL_CLUSTER_TOKEN --skip-hash-check"
fi
echo "$@" | grep -q -- "-advertise-client-urls"
if [[ $? -ne 0 ]]; then
  echo "setting default advertise urls for client"
  [[ -z "$cip" ]] && cip=$(dig +short $(hostname))
  [[ -z "$cip" ]] && exit 1
  ARGS="$ARGS --advertise-client-urls=http://${cip}:4001,http://${cip}:2379"
fi

[ $# -ne 0 ] && ARGS="$@ $ARGS"
unset TEST
echo "$@" | grep -q -- "--test"
if [[ $? -eq 0 ]]; then
  TEST=1
  ARGS=$(echo $ARGS | sed 's/--test *//')
fi

echo "--------------------------------------------"
echo $ARGS
echo "--------------------------------------------"

(sleep 3 && ETCDCTL_API=3 /bin/etcdctl put ping pong) &
if [[ -n "$TEST" ]]; then
  if [ "${ARGS:0:1}" = '-' ]; then
    echo "Running etcd [/bin/etcd $ARGS]"
    /bin/etcd $ARGS &
  else
    echo "Running etcd [$ARGS]"
    $ARGS &
  fi
  echo "Running test..."
  sleep 4
  ETCDCTL_API=3 timeout -t 1 /bin/etcdctl --endpoints=http://127.0.0.1:2379 get ping | grep pong && echo "passed"
  if [ $? -ne 0 ]; then
    echo "failed"
    exit 1
  fi
else
  if [ "${ARGS:0:1}" = '-' ]; then
    if [[ -f "/backup/.force-restore" ]]; then
      echo "Forcing restore of data from /backup/snapshot.db"
      ETCDCTL_API=3 etcdctl snapshot restore /backup/snapshot.db $RESTOREARGS
      if [ $? -ne 0 ]; then
        echo "failed"
        exit 1
      fi
      rm -Rf /data/*
      mv /data-restore/* /data/.
      rm -Rf /data-restore
      rm /backup/.force-restore
    fi
    exec flock -xn $LOCK_FILE /bin/etcd $ARGS
  else
    exec $ARGS
  fi
fi
