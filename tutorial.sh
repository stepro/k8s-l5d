#!/bin/bash
set -e

COLS=$(tput cols)

section() {
    echo
    echo "$@"
    echo "$@" | sed 's/./=/g'
}

sub-section() {
    echo
    echo "$@"
    echo "$@" | sed 's/./-/g'
}

body() {
    echo "$@" | fold -w $COLS -s
}

note() {
    INDENT=""
    while [ ${#INDENT} -lt $1 ]; do
        INDENT="$INDENT "
    done
    echo $2 | fold -w $((COLS-$1)) -s | sed "s/^/$INDENT/"
}

list() {
    for line; do
        echo -n " - "
        echo $line | fold -w $((COLS-3)) -s | head -n1
        echo $line | fold -w $((COLS-3)) -s | tail -n+2 | sed 's/^/   /'
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
    done
}

end-section() {
    echo [Press any key to continue or Ctrl+C to exit.]
    read -sn1
}

section 'Kubernetes + Linkerd'
body '
This tutorial shows a happy marriage of two projects in the Cloud Native Computing Foundation (CNCF) - Kubernetes and Linkerd - to achieve some interesting capabilities through dynamic request routing such as staged rollouts and virtual environments.

This tutorial assumes some basic knowledge of Kubernetes concepts and is designed to run inside a console session on a master node of a Kubernetes cluster. If you want to isolate this tutorial to a specific namespace in your Kubernetes cluster, say "l5dtest", run the following command and restart the tutorial:

kubectl create namespace l5dtest && \
kubectl config set-context $(kubectl config current-context) --namespace=l5dtest
'
end-section

section 'Getting Started'
body '
Kubernetes is already up and running. We just need to install linkerd:
'
code 'kubectl apply -f https://raw.githubusercontent.com/stepro/k8s-l5d/master/l5d.yaml' \
     'kubectl rollout status deployment/l5d'
body '
Nicely done! This is all we need to get started.
'
end-section

section 'Create a Service'
body '
Our first service is a very simple web application called "service-b" that we will use to illustrate some dynamic request routing capabilities. This service responds to requests with a string like "Hello from service B running on <hostname>". The code for this service is available at "https://github.com/stepro/service-b".

There are three versions of this service that have been pushed to a repository (https://hub.docker.com/r/stephpr/service-b) on Docker Hub:
'
list 'A stable committed version (stephpr/service-b:dd6eb164c5b3d31488377b48372db9451ac469f9)' \
     'A newly committed canary version (stephpr/service-b:f79630bf63832ae2ab78c25a18d889bf4f4fd378)' \
     'A private uncommitted version (stephpr/service-b:dev-stephpr-1e73ef836015)'
body '
We will show how all three versions of this service can be created in the same Kubernetes cluster behind a logical service named "service-b" that can dynamically route requests to one or more of the versioned services depending on both implicit and explicit routing rules.
'
end-section

sub-section 'Create the Logical Service'
body '
First, create the logical service "service-b" over the linkerd service:
'
code 'kubectl expose deployment l5d --name=service-b --port=80'
body '
Next, save the resulting cluster IP in an environment variable so we can easily curl this service:
'
code 'export SERVICE_B=$(kubectl get service service-b -o go-template={{.spec.clusterIP}})'
body '
Now try curling the service:
'
code 'curl -iSs $SERVICE_B'
body '
Not unexpectedly, this returns a 502 error as there are no versions of this service deployed yet.
'
end-section
exit 0

### Create the Stable Service
First, deploy and expose the stable version of the service:

```
kubectl run service-b-dd6eb16 --image=stephpr/service-b:dd6eb164c5b3d31488377b48372db9451ac469f9 --port=80
kubectl expose deployment service-b-dd6eb16 -l via=service-b,track=stable,run=service-b-dd6eb16 --port=80
```

There are two additional labels specified here that are of interest:

- `via`: indicates that this service is accessed via the logical service `service-b`
- `track`: an arbitrary label that identifies this as the stable version of the service

If desired, curl this specific version of the service to make sure it is working:

```
curl $(kubectl get service service-b-dd6eb16 -o go-template={{.spec.clusterIP}})
```

Notice it returns a message like `"Hello from service B running on <hostname>"`.

Next, tell the logical service about the specific version of the service we deployed:

```
kubectl annotate service service-b l5d=/svc/service-b-dd6eb16
```

Now curl the logical service to see that it routes to the stable version:

```
curl $SERVICE_B
```

This setup represents a baseline configuration of a logical service with one versioned service.

### Create the Canary Service 
We'll run through some similar steps to deploy and expose the canary version of the service:

```
kubectl run service-b-f79630b --image=stephpr/service-b:f79630bf63832ae2ab78c25a18d889bf4f4fd378 --port=80
kubectl expose deployment service-b-f79630b -l via=service-b,track=canary,run=service-b-f79630b --port=80
curl $(kubectl get service service-b-f79630b -o go-template={{.spec.clusterIP}})
```

Notice that this time, curl returns a message like `"HELLO from NEW service B running on <hostname>"`.

The logical service does not yet route to this version of the service by default; its annotation only points to the stable version of the service. However, we can access this version of the service via the logical service by specifying a special linkerd header:

```
curl $SERVICE_B -H 'l5d-dtab: /host/service-b => /svc/service-b-f79630b'
```

This rule essentially states that to host `service-b` should attempt to resolve to service `service-b-f79630b`.

The `track` label that was used earlier to identify the service versions as `stable` or `canary` can also be used in the routing rule:

```
curl $SERVICE_B -H 'l5d-dtab: /host => /label/track/canary'
```

Note that this rule is more general in that for *any* service, it routes to a version labeled `track=canary` if it exists. This makes it extremely easy to define virtual environments. We'll see a real example of this later.

### Create the Private Service
Once more, we'll run through similar steps to deploy and expose the private version of the service:

```
kubectl run service-b-dev-stephpr --image=stephpr/service-b:dev-stephpr-1e73ef836015 --port=80
kubectl expose deployment service-b-dev-stephpr -l via=service-b,dev=stephpr,run=service-b-dev-stephpr --port=80
```

Since this version is on neither the stable nor canary track, or for that matter any particular track, we labeled it differently, as `dev=stephpr`. Now just as we did to select the canary version, we can access this private version of the service using a linkerd header that selects services based on this label:

```
curl $SERVICE_B -H 'l5d-dtab: /host => /label/dev/stephpr'
```

You should see a message like `"HELLO from MY PRIVATE service B running on <hostname>"`.

Suppose a different `dev` label value is specified:

```
curl $SERVICE_B -H 'l5d-dtab: /host => /label/dev/johnsta'
```

Since no service with this label exists, linkerd falls back to the default rule which points at the stable version.

### Rollout the Canary Service
Let's perform a random percentage-based staged rollout of the canary service. This involves updating the `l5d` annotation on the logical service to change the default routing rule for the service.

We start by rolling out the canary version to 5% of users:

```
kubectl annotate --overwrite service service-b l5d='95*/label/track/stable/service-b & 5*/label/track/canary/service-b'
```

You can observe the effect of this change by running curl a number of times:

```
for ((i=0; i<200; i++)); do echo $(curl -Ss $SERVICE_B); done
```

You should observe that the new message is returned approximately 5% of the time.

For more obvious effect, let's roll out the canary version to 50% of users:

```
kubectl annotate --overwrite service service-b l5d='50*/label/track/stable/service-b & 50*/label/track/canary/service-b'
```

Again, observe the effect of this change:

```
for ((i=0; i<200; i++)); do echo $(curl -Ss $SERVICE_B); done
```

The new message appears approximately half of the time.

Finally, complete the rollout by fixing the default routing rule to the new service version:

```
kubectl annotate --overwrite service service-b l5d=/svc/service-b-f79630b
```

Verify that only the new message now appears:

```
for ((i=0; i<200; i++)); do echo $(curl -Ss $SERVICE_B); done
```

At this point, we can delete the original deployment and service and re-label the canary as the stable track:

```
kubectl delete deployment,service -l run=service-b-dd6eb16
kubectl label --overwrite service service-b-f79630b track=stable
```

This completes the staged rollout of the canary version, eventually replacing the existing stable version which was then deleted from the cluster.

## Create a Second Service
The real power of dynamic request routing comes into play when there are multiple services interacting with one another. With this in mind, let's deploy a few versions of a second service `service-a` that calls `service-b`. This service incorporates a basic web UI that calls an `/api` endpoint that returns a string like `"Hello from service A running on <hostname-a> and Hello from service B running on <hostname-b>"`. The second half of this string is the result of calling `service-b`. The code for this service is available [here](https://github.com/stepro/service-a).

Once again, there are three versions of this service that have been pushed to a [repository](https://hub.docker.com/r/stephpr/service-a) on Docker Hub:

- A stable committed version (stephpr/service-a:240bf8b84cb9bd71f4d329362d93be42ce2c65e6)
- A newly committed canary version (stephpr/service-a:726840f2df9e2a6e3e9e2ce92f3307b2735f1adf)
- A private uncommitted version (stephpr/service-b:dev-johnsta-fafb8856f7f7)

Run these commands to deploy and expose the logical service `service-a` and its three versions:

```
kubectl expose deployment l5d --name=service-a --port=80
export SERVICE_A=$(kubectl get service service-a -o go-template={{.spec.clusterIP}})
kubectl run service-a-240bf8b --image=stephpr/service-a:240bf8b84cb9bd71f4d329362d93be42ce2c65e6 --port=80
kubectl expose deployment service-a-240bf8b -l via=service-a,track=stable,run=service-a-240bf8b --port=80
kubectl annotate service service-a l5d=/svc/service-a-240bf8b
kubectl run service-a-726840f --image=stephpr/service-a:726840f2df9e2a6e3e9e2ce92f3307b2735f1adf --port=80
kubectl expose deployment service-a-726840f -l via=service-a,track=canary,run=service-a-726840f --port=80
kubectl run service-a-dev-johnsta --image=stephpr/service-a:dev-johnsta-fafb8856f7f7 --port=80
kubectl expose deployment service-a-dev-johnsta -l via=service-a,dev=johnsta,run=service-a-dev-johnsta --port=80
```

Verify that the service is correctly routing to the stable version:

```
curl $SERVICE_A/api
```

You should see a message like `"Hello from service A running on <hostname-a> and HELLO from NEW service B running on <hostname-b>"` (remember that we just recently upgraded `service-b` hence the NEW message).

Try routing to the canary and private versions:

```
curl $SERVICE_A/api -H 'l5d-dtab: /host => /label/track/canary'
curl $SERVICE_A/api -H 'l5d-dtab: /host => /label/dev/johnsta'
```

You should see messages that start with `"HELLO from NEW service A running on <hostname-a>"` and `"HELLO from MY PRIVATE service A running on <hostname-a>"`.

## Deep Request Routing
Suppose we try this:

```
curl $SERVICE_A/api -H 'l5d-dtab: /host => /label/dev/stephpr'
```

We might expect that this will route to the stable version of `service-a` and the private version of `service-b`, since that service is labeled with `dev=stephpr`. In an ideal work, this would just work. However, in reality, `service-a` must propagate linkerd headers from its own incoming request to its outgoing request to `service-b`.

Instead of hard-coding knowledge of this linkerd header, `service-a` looks for a well-known meta-header `Context-Headers` that lists the headers that it should propagate to downstream services. Wildcards are allowed in the list. This approach to header propagation is general purpose and minimizes code changes across services.

It turns out that linkerd expects all headers that start with `l5d-ctx-` to be propagated through services, so let's try this:

```
curl $SERVICE_A/api -H 'Context-Headers: l5d-ctx-*' -H 'l5d-dtab: /host => /label/dev/stephpr'
```

It works! You will see a message like `"Hello from service A running on <hostname-a> and HELLO from MY PRIVATE service B running on <hostname-b>"`.

Deep request routing introduces a very powerful tool for modern, micro-service based applications: the ability to inject a private, maybe even debuggable version of a service deep inside a large graph of micro-services that constitute an application, without having to replicate some or all of those micro-services just to make the service function.

## Virtual Environments
The last part of this tutorial brings together everything described above to create a virtual environment that builds on and derives from a baseline or default environment. Contrast this to a traditional environment in which a full stack of components must be spun up.

Currently we have three versions of `service-a` - stable, canary and private (to johnsta) - and two versions of `service-b`: stable and private (to stephpr). Let's imagine first that stephpr wishes to create a virtual environment that includes all of his private versions of services, and for any service that does not exist, to pick any canary version over the stable version.

With linkerd routing, this is trivial:

```
curl $SERVICE_A/api -H 'Context-Headers: l5d-ctx-*' -H 'l5d-dtab: /host => /label/dev/stephpr | /label/track/canary'
```

This will produce a message like `"HELLO from NEW service A running on <hostname-a> and HELLO from MY PRIVATE service B running on <hostname-b>"`. For `service-a`, there was no service labeled `dev=stephpr` but there was one labeled `track=canary`, so it picked that one. For `service-b`, there was a service labeled `dev=stephpr` so it picked that one.

Now suppose johnsta and stephpr are working together on new versions of `service-a` and `service-b` that relate to a particular feature `mycoolfeature`. What they want to do is specify a route that matches the private versions of both `service-a` and `service-b`.

They can do this by specifying multiple rules in the linkerd header:

```
curl $SERVICE_A/api -H 'Context-Headers: l5d-ctx-*' -H 'l5d-dtab: /host/service-a => /label/dev/johnsta/service-a; /host/service-b => /label/dev/stephpr/service-b'
```

Unfortunately, this is quite verbose. An alternative is to add a common label to both services and then route based on that label:

```
kubectl label service service-a-dev-johnsta feature=mycoolfeature
kubectl label service service-b-dev-stephpr feature=mycoolfeature
```

And then:

```
curl $SERVICE_A/api -H 'Context-Headers: l5d-ctx-*' -H 'l5d-dtab: /host => /label/feature/mycoolfeature'
```

## Want more?
The patterns presented here are implemented in this repository. You can inspect the [l5d.yaml](https://raw.githubusercontent.com/stepro/k8s-l5d/master/l5d.yaml) file to see how linkerd and other components were configured to streamline the above scenarios.

This repository supports some features not yet described in this tutorial, such as a linkerd-aware ingress proxy that enables a user to specify a simplified routing rule as part of a query string. If these scenarios are interesting to you, please send a message to [me](https://github.com/stepro) and I'd be happy to follow up!

## Cleaning up
To remove all traces of this tutorial, simply run:

```
kubectl delete namespace l5dtest
```

Kubernetes will eventually purge all contents of the namespace and delete it.
