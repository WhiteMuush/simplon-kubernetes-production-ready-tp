# Brief

## Project context

You have deployed your first application on Kubernetes, congratulations! It is even reachable from your machine by typing http://localhost:8080 in your browser's address bar, which means you exposed it correctly to the outside of the cluster, probably with a Service of type LoadBalancer or NodePort.

Today, we need you to help another team that is trying to deploy its microservices application on their Kubernetes cluster.

They have an API written in Go, which talks to two other services, also written in Go, whose purpose is to fetch information about books and movies. They want the three applications to be deployed on Kubernetes, replicated several times, and the API to be reachable from outside the cluster. The API must be able to talk to the two services through the cluster's internal network. The movies and books services must not be reachable from outside.

## The API

It is a Go application that needs two environment variables to work:

- `BOOKS_API_HOST`
- `MOVIES_API_HOST`

With Docker Compose, we would have put the names of those applications' containers here, but this is not possible on Kubernetes, so we need to find a way to expose them, retrieve their "host", and set it as an environment variable in our API Deployment.

This kind of API is called an "API Gateway", mainly because its role is to aggregate data from several underlying services.

## The Docker image

If you look at the project's single Dockerfile, you will see that a single image is built for the three applications. So you will need to configure its Pods correctly so they start on the right application each time ("movies", "books" or "api").

Once the image is built, you will need to find a way to make it available in Kubernetes, using the "kind load docker-image" feature.

## HA

The application is meant to be used in production. So it must be deployed in "high availability" mode, meaning distributed and replicated across several worker nodes. No deployment on the control-plane.

## Bonus

- The N replicas of a same application are not deployed on the same worker node (anti-affinity rule)
- Resources (CPU & Memory) are assigned to the containers (for example 0.1 CPU, 64MB RAM per container/pod/replica/app)
- Replace the "hardcoded" environment variables in the YAML with a ConfigMap

## Expected response

On a call to http://localhost:8080

```json
{
  "app": "API Gateway",
  "data": {
    "books": [
      "Book 1",
      "Book 2",
      "Book 3"
    ],
    "movies": [
      "Movie 1",
      "Movie 2",
      "Movie 3"
    ]
  }
}
```
