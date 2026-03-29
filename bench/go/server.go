package main

import (
	"encoding/json"
	"fmt"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/json" {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
		} else if r.URL.Path == "/health" {
			w.Header().Set("Content-Type", "text/plain")
			fmt.Fprint(w, "ok")
		} else {
			w.Header().Set("Content-Type", "text/plain")
			fmt.Fprint(w, "Hello from Go!")
		}
	})

	fmt.Println("Go server on http://127.0.0.1:8080")
	http.ListenAndServe("127.0.0.1:8080", nil)
}
