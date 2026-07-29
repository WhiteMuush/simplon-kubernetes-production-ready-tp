package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
)

type BackendData struct {
	App  string   `json:"app"`
	Data []string `json:"data"`
}

func main() {
	booksAPIHost, ok := os.LookupEnv("BOOKS_API_HOST")
	if !ok {
		log.Fatal("environment variable 'BOOKS_API_HOST' is not set")
	}

	moviesAPIHost, ok := os.LookupEnv("MOVIES_API_HOST")
	if !ok {
		log.Fatal("environment variable 'MOVIES_API_HOST' is not set")
	}

	booksAPIURL := fmt.Sprintf("http://%s/books", booksAPIHost)
	moviesAPIURL := fmt.Sprintf("http://%s/movies", moviesAPIHost)

	log.Printf("Books API URL: %s", booksAPIURL)
	log.Printf("Movies API URL: %s", moviesAPIURL)

	r := gin.Default()

	r.GET("/data", func(c *gin.Context) {
		booksResponse, err := http.Get(booksAPIURL)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("failed to fetch books: %s", err.Error())})
			return
		}
		defer booksResponse.Body.Close()

		moviesResponse, err := http.Get(moviesAPIURL)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("failed to fetch movies: %s", err.Error())})
			return
		}
		defer moviesResponse.Body.Close()

		var booksData, moviesData BackendData

		json.NewDecoder(booksResponse.Body).Decode(&booksData)
		json.NewDecoder(moviesResponse.Body).Decode(&moviesData)

		c.JSON(http.StatusOK, gin.H{
			"app": "API Gateway",
			"data": gin.H{
				"books":  booksData.Data,
				"movies": moviesData.Data,
			},
		})
	})

	if err := r.Run(); err != nil {
		log.Fatalf("failed to run server: %v", err)
	}
}
