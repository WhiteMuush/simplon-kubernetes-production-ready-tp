package main

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	r.GET("/books", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"app":  "Books API",
			"data": []string{"Book 1", "Book 2", "Book 3"},
		})
	})

	if err := r.Run(); err != nil {
		log.Fatalf("failed to run server: %v", err)
	}
}
