package main

import (
	"log"
	"github.com/nknorg/nkn-sdk-go"
)

func main() {
	account, err := nkn.NewAccount(nil)
	if err != nil {
		log.Fatal(err)
	}

	log.Println("Connecting to NKN...")
	client, err := nkn.NewMultiClient(account, "tester", nil)
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}

	log.Println("Waiting for connection...")
	<-client.OnConnect.C
	log.Println("Connected as", client.Address())

	dest := "nimclaw-bot.840c706c9ce0302cb4970be97bf9a8e1c808bb53ffa6c0b6c29d9f408bc949b8"
	code := "81706"

	log.Println("Sending code", code, "to", dest)
	_, err = client.Send(nkn.NewStringArray(dest), []byte(code), nil)
	if err != nil {
		log.Fatalf("Failed to send message: %v", err)
	}

	log.Println("Sent pairing code successfully!")
	client.Close()
}
