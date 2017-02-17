#!/bin/bash

COLS=$(tput cols)
RESET='\033[0m'
NORMAL='\033[0;32m'
UNDERLINE='\033[4;32m'
GRAY='\033[1;30m'

text() {
    echo -en ${1:-$NORMAL}
    while read line; do
        echo $line
    done
    echo -en $RESET
}

section() {
    echo
    echo "$@" | text
    echo "$@" | sed 's/./=/g' | text
}

sub-section() {
    echo
    echo "$@" | text $UNDERLINE
}

body() {
    echo "$@" | fold -w $COLS -s | text
}

list() {
    for line; do
        echo -en $NORMAL" - "$RESET
        echo $line | fold -w $((COLS-3)) -s | head -n1 | text
        echo $line | fold -w $((COLS-3)) -s | tail -n+2 | sed 's/^/   /' | text
    done
}

code() {
    FIRST=1
    for line; do
        if [ "$FIRST" == "1" ]; then
            echo -n '$ '
        else
            echo ' && \' && echo -n '  '
        fi
        echo -n $line
        FIRST=
    done
    while true; do
        read -sn1 key
        if [ "$key" == "" ]; then
            echo
            break
        fi
    done
    for line; do
        eval $line
        while [ $? -ne 0 ]; do
          echo -e $GRAY[Command failed - press any key to try again or Ctrl+C to exit]$RESET
          read -sn1
          eval $line
        done
    done
}

end-section() {
    echo -e $GRAY[Press any key to continue or Ctrl+C to exit]$RESET
    read -sn1
}

cleanup() {
    echo
    echo Cleaning up...
    kubectl delete svc,deploy service-a-dev-johnsta 2> /dev/null
    kubectl delete svc,deploy service-a-726840f 2> /dev/null
    kubectl delete svc,deploy service-a-240bf8b 2> /dev/null
    kubectl delete svc service-a 2> /dev/null
    kubectl delete svc,deploy service-b-dev-stephpr 2> /dev/null
    kubectl delete svc,deploy service-b-f79630b 2> /dev/null
    kubectl delete svc,deploy service-b-dd6eb16 2> /dev/null
    kubectl delete svc service-b 2> /dev/null
    kubectl delete svc,deploy,configmap l5d 2> /dev/null
    echo done
}

trap 'cleanup; exit 130' INT

section 'Kubernetes + Linkerd: External Services'
body '
This tutorial builds on the first Kubernetes + Linkerd tutorial, available at "https://raw.githubusercontent.com/stepro/k8s-l5d/master/tutorial.sh". If you have not taken that tutorial, please start there.

In this tutorial, we will externally expose the "service-a" service and show how to route it through a linkerd-aware ingress proxy that enables some interesting routing scenarios without the complexity of linkerd headers.

This tutorial assumes basic knowledge of Kubernetes concepts and some familiarity with the kubectl CLI. It is designed to run inside a console session on a master node of a Kubernetes cluster. If you want to isolate this tutorial to a specific namespace in your Kubernetes cluster, say "l5dtest", run the following command and restart the tutorial:

kubectl create namespace l5dtest && \\
kubectl config set-context $(kubectl config current-context) --namespace=l5dtest

If at any time you press Ctrl+C to exit the tutorial, it will delete all Kubernetes objects that it created. If you allow the tutorial to run to completion, it will leave the Kubernetes objects behind for further inspection.
'
end-section

section 'Getting Started'
body '
Kubernetes is already up and running. To pick up from where the first tutorial left off, we need to ensure linkerd is installed as well as the various objects from the first tutorial:
'
code 'kubectl apply -f https://raw.githubusercontent.com/stepro/k8s-l5d/master/l5d.yaml' \
     'kubectl apply -f https://raw.githubusercontent.com/stepro/k8s-l5d/master/tutorial.yaml'
body '
Next, we patch "service-a" so that it is of type "LoadBalancer", which will create an external IP address through which we can access the service (it can take 2-5 minutes for the external IP to become available, so be patient):
'
code 'kubectl patch service service-a -p "{\"spec\":{\"type\":\"LoadBalancer\"}}"' \
     'echo -n waiting for external IP...' \
     'until kubectl get service service-a -o jsonpath={.status.loadBalancer.ingress[0].ip} >/dev/null 2>&1; do sleep 1; echo -n .; done' \
     'echo found' \
     'export SERVICE_A=$(kubectl get service service-a -o jsonpath={.status.loadBalancer.ingress[0].ip})' \
     'curl $SERVICE_A/api'
body '

Great! We are ready to get started.
'
end-section

section 'Review Linkerd Routing'
body '
Now that "service-a" has been externally exposed, let us quickly review some of the linkerd routing capabilities.

We have three versions of "service-a" - stable, canary and private (to johnsta) - and two versions of "service-b": stable and private (to stephpr).

Using the external IP for "service-a", we can apply various forms of routing, such as:
'
code 'curl $SERVICE_A/api -H "Context-Headers: l5d-ctx-*" -H "l5d-dtab: /host => /label/dev/johnsta"'
body '

This routes to the private "service-a" and the stable "service-b". Similarly:
'
code 'curl $SERVICE_A/api -H "Context-Headers: l5d-ctx-*" -H "l5d-dtab: /host => /label/dev/stephpr"'
body '

This routes to the stable "service-a" and the private "service-b".

This is all well and good, but it is not particularly easy to pass custom headers as an external caller, especially if the external service is something like a web frontend which, when accessed through a browser, creates many sub-requests to the service to retrieve additional content such as CSS and JavaScript files.

Without any specific aids, the web frontend would need to explicitly ensure all sub-requests include the necessary headers to route to the correct version of the service. This would require some deep changes to the web frontend code that is hard to maintain.

There must be a better way, and there is, by using a special linkerd-aware ingress proxy.
'
end-section

section 'Using Linkerd Ingress'
body '
The linkerd service that was originally deployed comes with a built-in ingress proxy designed for external services. To use it, we change the "service-a" service to talk to a different linkerd port:
'
code 'kubectl patch service service-a -p "{\"spec\":{\"ports\":[{\"port\":80,\"targetPort\":32080}]}}"'
body '
This port is implemented by a custom nginx proxy that ultimately routes to linkerd but does some nice things for us before it gets there. In particular:
'
list 'It makes a sub-request to an arbitrary context service running in the same pod;' \
     'The context service produces context headers from the incoming request;' \
     'These context headers are specified in a "Context-Headers" header;' \
     'All of these headers are added to the request eventually sent to "service-a";' \
     'Before returning a response to the caller, some of the context is set in a cookie;' \
     'When another request is made, context from the cookie is used if not otherwise provided.'
body '
For this tutorial, a basic context service is implemented as a Node.JS web server.
'
end-section

section 'Understanding the Context Service'
body '
The basic context service for this tutorial implements the following logic:
'
list 'Look for a "user" query parameter or a "User" header. If neither exist, return 401 Unauthorized.' \
     'Ensure the "User" header is set to the specified user (this simulates a "signed in" user).' \
     'If the user is an email address ending with "@microsoft.com", then allow custom routing rules.' \
     'If a "l5d-label" query parameter is provided, then set the header "l5d-dtab: /host=>/label/<value>".' \
     'Otherwise ensure any existing l5d-dtab header is returned as part of the context.'
body '
The code for this context service is available at "https://raw.githubusercontent.com/stepro/k8s-l5d/master/contextd/basic/server.js".

We can test out the logic implemented by this context service by making various calls to the external "service-a" service.
'
end-section

section 'Evaluating the Context Service'
body '
First, we can make a call with no particular arguments supplied:
'
code 'curl $SERVICE_A/api'
body '
Notice that this returns 401 Unauthorized because no user is "signed in". We can fix that by adding user information:
'
code 'curl $SERVICE_A/api?user=foo@bar.com'
body '

Now the "signed in" user gets a result using the default routing rules.

Next, we can try adding a custom routing rule on the query string:
'
code 'curl "$SERVICE_A/api?user=foo@bar.com&l5d-label=dev/johnsta"'
body '

Hmm. This had no effect, even though there is a private version of "service-a" that should have been called. What happened?

Well, remember the context service implemented logic that prevented just anybody from using custom routing rules. In particular, it only allows users with email addresses at microsoft.com to specify rules.

Given this, we can try again using a privileged user with the same routing rule:
'
code 'curl "$SERVICE_A/api?user=foo@microsoft.com&l5d-label=dev/johnsta"'
body '

Great, that worked!

Now that you understand what the context service does, try browsing to the external IP ('$SERVICE_A') from your favorite browser. The root URL offers a simple UI that shows the message produced by the "/api" path.

By using a browser, you can appreciate how cookies are used to maintain context across requests, such that the code in "service-a" remains agnostic to linkerd and management of context in general. It simply expects to receive a "Context-Headers" header and knows that this identifies context headers for the entire logical request that should be propagated from one service to the next.

Clearly in a more realistic situation, the context service used in this tutorial would be replaced with something more advanced that reads real user information (such as through claims extracted from an OAuth token) and performs more interesting logic, such as bucketizing a whitelist of users or groups into the canary environment.
'
end-section

section 'Finishing up'
body '
The patterns presented here are implemented in the following repository:

https://github.com/stepro/k8s-l5d

Any and all feedback on these patterns and whether they would be useful to you in a production context is greatly appreciated. Feel free to contact me at stephpr@microsoft.com and I would be happy to chat!

Reminder: If you would like to clean up the objects created by this tutorial, hit Ctrl+C now. You can also clean them up later by restarting the tutorial and immediately hitting Ctrl+C.

Thank you for running through this tutorial!
'
end-section
