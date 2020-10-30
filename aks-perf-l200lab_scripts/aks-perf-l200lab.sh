#!/bin/bash

# script name: aks-perf-l200lab.sh
# Version v0.0.5 20201030
# Set of tools to deploy L200 Azure containers labs

# "-g|--resource-group" resource group name
# "-n|--name" AKS cluster name
# "-l|--lab" Lab scenario to deploy
# "-v|--validate" Validate a particular scenario
# "-r|--region" region to deploy the resources
# "-h|--help" help info
# "--version" print version

# read the options
TEMP=`getopt -o g:n:l:r:hv --long resource-group:,name:,lab:,region:,help,validate,version -n 'aks-perf-l200lab.sh' -- "$@"`
eval set -- "$TEMP"

# set an initial value for the flags
RESOURCE_GROUP=""
CLUSTER_NAME=""
LAB_SCENARIO=""
LOCATION="eastus2"
VALIDATE=0
HELP=0
VERSION=0

while true ;
do
    case "$1" in
        -h|--help) HELP=1; shift;;
        -g|--resource-group) case "$2" in
            "") shift 2;;
            *) RESOURCE_GROUP="$2"; shift 2;;
            esac;;
        -n|--name) case "$2" in
            "") shift 2;;
            *) CLUSTER_NAME="$2"; shift 2;;
            esac;;
        -l|--lab) case "$2" in
            "") shift 2;;
            *) LAB_SCENARIO="$2"; shift 2;;
            esac;;
        -r|--region) case "$2" in
            "") shift 2;;
            *) LOCATION="$2"; shift 2;;
            esac;;    
        -v|--validate) VALIDATE=1; shift;;
        --version) VERSION=1; shift;;
        --) shift ; break ;;
        *) echo -e "Error: invalid argument\n" ; exit 3 ;;
    esac
done

# Variable definition
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPT_NAME="$(echo $0 | sed 's|\.\/||g')"
SCRIPT_VERSION="Version v0.0.5 20201030"

# Funtion definition

# az login check
function az_login_check () {
    if $(az account list 2>&1 | grep -q 'az login')
    then
        echo -e "\nWarning: You have to login first with the 'az login' command before you can run this lab tool\n"
        az login -o table
    fi
}

# check resource group and cluster
function check_resourcegroup_cluster () {
    RG_EXIST=$(az group show -g $RESOURCE_GROUP &>/dev/null; echo $?)
    if [ $RG_EXIST -ne 0 ]
    then
        echo -e "\nCreating resource group ${RESOURCE_GROUP}...\n"
        az group create --name $RESOURCE_GROUP --location $LOCATION &>/dev/null
    else
        echo -e "\nResource group $RESOURCE_GROUP already exists...\n"
    fi

    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -eq 0 ]
    then
        echo -e "\nCluster $CLUSTER_NAME already exists...\n"
        echo -e "Please remove that one before you can proceed with the lab.\n"
        exit 4
    fi
}

# validate cluster exists
function validate_cluster_exists () {
    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -ne 0 ]
    then
        echo -e "\nERROR: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP does not exists...\n"
        exit 5
    fi
}

# Lab scenario 1
function lab_scenario_1 () { 
    az aks create \
        --resource-group $RESOURCE_GROUP \
        --name $CLUSTER_NAME \
        --location $LOCATION \
        --node-count 1 \
        --tag l200lab=${LAB_SCENARIO} \
        --generate-ssh-keys \
        -o table

    validate_cluster_exists

    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: importantapp
  labels:
    app: importantapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: importantapp
  template:
    metadata:
      labels:
        app: importantapp
    spec:
        containers:
        - name: importantpod
          image: polinux/stress
          resources:
            requests:
              memory: "50Mi"
            limits:
              memory: "200Mi"
          command: ["stress"]
          args: ["--vm", "1", "--vm-bytes", "300M", "--vm-hang", "1"]
EOF

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"

    echo -e "\n\n********************************************************"
    echo -e "\nThe deployment \"importantapp\" has a pod in CrashLoopBackoff."
    echo -e "\nIdentify why the pod is failing and modify the deployment resources if necesary to fix the issue."
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_1_validation () {
    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags.l200lab -o tsv 2>/dev/null)"
    echo -e "\n+++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "Running validation for Lab scenario $LAB_SCENARIO\n"
    if [ -z $LAB_TAG ]
    then
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        RUNNING_POD="$(kubectl get po -l app=importantapp | grep Running | wc -l 2>/dev/null)"
        if [ $RUNNING_POD -eq 1 ]
        then
            echo -e "\n\n========================================================"
            echo -e "\nThe importantapp deployment looks good now, the keyword for the assesment is:\n\nmuggiest minuscule decently\n"
        else
            echo -e "\nScenario $LAB_SCENARIO is still FAILED\n"
        fi
    else
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

# Lab scenario 2
function lab_scenario_2 () {
    az aks create \
        --resource-group $RESOURCE_GROUP \
        --name $CLUSTER_NAME \
        --location $LOCATION \
        --node-count 1 \
        --tag l200lab=${LAB_SCENARIO} \
        --generate-ssh-keys \
        -o table

    validate_cluster_exists

    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Service
metadata:
  name: productcatalogue
  labels:
    app: productcatalogue
spec:
  type: NodePort
  selector:
    app: productcatalogue
  ports:
  - protocol: TCP
    port: 8020
    name: http
---
apiVersion: v1
kind: ReplicationController
metadata:
  name: productcatalogue
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: productcatalogue
    spec:
      containers:
      - name: productcatalogue
        image: danielbryantuk/djproductcatalogue:1.0
        ports:
        - containerPort: 8020
        livenessProbe:
          httpGet:
            path: /healthcheck
            port: 8025
          initialDelaySeconds: 30
          timeoutSeconds: 1
---
apiVersion: v1
kind: Service
metadata:
  name: shopfront
  labels:
    app: shopfront
spec:
  type: NodePort
  selector:
    app: shopfront
  ports:
  - protocol: TCP
    port: 8010
    name: http

---
apiVersion: v1
kind: ReplicationController
metadata:
  name: shopfront
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: shopfront
    spec:
      containers:
      - name: djshopfront
        image: danielbryantuk/djshopfront:1.0
        ports:
        - containerPort: 8010
        livenessProbe:
          httpGet:
            path: /health
            port: 8010
          initialDelaySeconds: 30
          timeoutSeconds: 1
---
apiVersion: v1
kind: Service
metadata:
  name: stockmanager
  labels:
    app: stockmanager
spec:
  type: NodePort
  selector:
    app: stockmanager
  ports:
  - protocol: TCP
    port: 8030
    name: http

---
apiVersion: v1
kind: ReplicationController
metadata:
  name: stockmanager
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: stockmanager
    spec:
      containers:
      - name: stockmanager
        image: danielbryantuk/djstockmanager:1.0
        ports:
        - containerPort: 8030
        livenessProbe:
          httpGet:
            path: /health
            port: 8030
          initialDelaySeconds: 30
          timeoutSeconds: 1
EOF

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    component: custom-check
  name: custom-check
  namespace: kube-system
spec:
  selector:
    matchLabels:
      component: custom-check
      tier: node
  template:
    metadata:
      labels:
        component: custom-check
        tier: node
    spec:
      containers:
      - name: custom-check
        image: alpine
        imagePullPolicy: IfNotPresent
        command:
          - nsenter
          - --target
          - "1"
          - --mount
          - --uts
          - --ipc
          - --net
          - --pid
          - --
          - sh
          - -c
          - |
            while true; do ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -2 | grep -v 'PPID' | awk '{print \$1}'; sleep 30; done
        resources:
          requests:
            cpu: 50m
        securityContext:
          privileged: true
      dnsPolicy: ClusterFirst
      hostPID: true
      tolerations:
      - effect: NoSchedule
        operator: Exists
      restartPolicy: Always
  updateStrategy:
    type: OnDelete
EOF

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"

    echo -e "\n\n********************************************************"
    echo -e "\nConnect to the worker node and identify what is the process ID that is consuming more memory"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_2_validation () {
    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags.l200lab -o tsv 2>/dev/null)"
    echo -e "\n+++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "Running validation for Lab scenario $LAB_SCENARIO\n"
    if [ -z $LAB_TAG ]
    then
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        TOP_PID="$(kubectl logs --tail=1 -l component=custom-check -n kube-system 2>/dev/null)"
        echo -e "Enter the process ID which is using most of the memory from the node\n"
        read -p 'PID: ' USER_PID
        RE='^[0-9]+$'
        if ! [[ $USER_PID =~ $RE ]]
        then
            echo -e "ERROR: The PID value $USER_PID is not valid...\n"
            exit 12
        fi
        if [ "$TOP_PID" == "$USER_PID" ]
        then
            echo -e "\n\n========================================================"
            echo -e "\nYour answer is correct, the keyword for the assesment is:\n\nsturdy laundering grammatically\n"
        else
            echo -e "\nIncorrect answer provided, try again...\n"
        fi
    else
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

#if -h | --help option is selected usage will be displayed
if [ $HELP -eq 1 ]
then
	echo "aks-perf-l200lab usage: aks-perf-l200lab -g <RESOURCE_GROUP> -n <CLUSTER_NAME> -l <LAB#> [-v|--validate] [-r|--region] [-h|--help] [--version]"
    echo -e "\nHere is the list of current labs available:\n
***************************************************************
*\t 1. Pod in CrashLoopBackOff
*\t 2. Memory usage
***************************************************************\n"
echo -e '"-g|--resource-group" resource group name
"-n|--name" AKS cluster name
"-l|--lab" Lab scenario to deploy
"-r|--region" region to create the resources
"-v|--validate" Validate a particular scenario
"--version" print version of aks-perf-l200lab
"-h|--help" help info\n'
	exit 0
fi

if [ $VERSION -eq 1 ]
then
	echo -e "$SCRIPT_VERSION\n"
	exit 0
fi

if [ -z $RESOURCE_GROUP ]; then
	echo -e "Error: Resource group value must be provided. \n"
	echo -e "aks-perf-l200lab usage: aks-perf-l200lab -g <RESOURCE_GROUP> -n <CLUSTER_NAME> -l <LAB#> [-v|--validate] [-r|--region] [-h|--help] [--version]\n"
	exit 7
fi

if [ -z $CLUSTER_NAME ]; then
	echo -e "Error: Cluster name value must be provided. \n"
	echo -e "aks-perf-l200lab usage: aks-perf-l200lab -g <RESOURCE_GROUP> -n <CLUSTER_NAME> -l <LAB#> [-v|--validate] [-r|--region] [-h|--help] [--version]\n"
	exit 8
fi

if [ -z $LAB_SCENARIO ]; then
	echo -e "Error: Lab scenario value must be provided. \n"
	echo -e "aks-perf-l200lab usage: aks-perf-l200lab -g <RESOURCE_GROUP> -n <CLUSTER_NAME> -l <LAB#> [-v|--validate] [-r|--region] [-h|--help] [--version]\n"
    echo -e "\nHere is the list of current labs available:\n
***************************************************************
*\t 1. Pod in CrashLoopBackOff
*\t 2. Memory usage
***************************************************************\n"
	exit 9
fi

# lab scenario has a valid option
if [[ ! $LAB_SCENARIO =~ ^[1-2]+$ ]];
then
    echo -e "\nError: invalid value for lab scenario '-l $LAB_SCENARIO'\nIt must be value from 1 to 2\n"
    exit 10
fi

# main
echo -e "\nWelcome to the L200 Troubleshooting sessions
********************************************

This tool will use your internal azure account to deploy the lab environment.
Verifing if you are authenticated already...\n"

# Verify az cli has been authenticated
az_login_check

if [ $LAB_SCENARIO -eq 1 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_1

elif [ $LAB_SCENARIO -eq 1 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_1_validation

elif [ $LAB_SCENARIO -eq 2 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_2

elif [ $LAB_SCENARIO -eq 2 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_2_validation

else
    echo -e "\nError: no valid option provided\n"
    exit 11
fi

exit 0