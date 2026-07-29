FROM golang:1.26 AS builder

WORKDIR /app

# Dependencies
COPY go.mod go.sum ./
RUN go mod download

# Build
COPY . .
RUN CGO_ENABLED=0 go build -o api ./cmd/api
RUN CGO_ENABLED=0 go build -o books ./cmd/books
RUN CGO_ENABLED=0 go build -o movies ./cmd/movies

FROM gcr.io/distroless/static-debian12 AS runtime

WORKDIR /app

COPY --from=builder /app/api .
COPY --from=builder /app/books .
COPY --from=builder /app/movies .
