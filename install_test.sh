#!/bin/bash
#
# Fast recreate syndesis environment for testing
#

PROJECT=${1:-syndesis}

function wait_for() {
	local cmd=$1
	local progress=''

        while true 
        do
		eval $cmd
		local rc=$?

        	progress="${progress}."
        	echo -ne "$progress\r"
        	sleep 1
		
		if [[ "$rc" == "1" ]]
		then
			break
		fi
        done
	echo -ne '\n'
}

function create_project() {
	local project=$1

	echo "Creating namespace $project ..."
        oc new-project $project >/dev/null 2>&1

	echo "Waiting for namespace $project to be ready"
	wait_for "oc get project $project | grep NotFound >/dev/null 2>&1" 

	echo "Namespace $project is ready"
}

function delete_project() {
	local project=$1

	echo "Deleting namespace $project"
        oc delete project $project >/dev/null 2>&1

	echo "Waiting for namespace $project to be deleted"
	wait_for "oc get project $project >/dev/null 2>&1" 

	echo "Namespace $project is deleted"
}

function recreate_project() {
	local project=$1

	delete_project $project
	create_project $project
}

[[ -z $DEVELOPERS_REDHAT_COM_USER ]] && echo "DEVELOPERS_REDHAT_COM_USER not set" && exit 1
[[ -z $DEVELOPERS_REDHAT_COM_PASS ]] && echo "DEVELOPERS_REDHAT_COM_PASS not set" && exit 1

recreate_project $PROJECT
oc project $PROJECT

./install_ocp.sh --setup;

oc create secret docker-registry syndesis-pull-secret \
	--docker-server=registry.redhat.io \
	--docker-username=$DEVELOPERS_REDHAT_COM_USER \
	--docker-password=$DEVELOPERS_REDHAT_COM_PASS

./install_ocp.sh

 exit 0
