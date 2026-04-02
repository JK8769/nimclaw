package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/hex"
	"encoding/json"
	"sync"
	"unsafe"

	"github.com/nknorg/nkn-sdk-go"
)

type NknMessage struct {
	Src  string
	Data string
}

type FFIResult struct {
	Result string `json:"result"`
	Data   string `json:"data"`
	Error  string `json:"error"`
	Src    string `json:"src"`
}

var (
	activeClients = make(map[string]*nkn.MultiClient)
	messageQueues = make(map[string]chan NknMessage)
	mutex         sync.Mutex
)

func toJSON(res FFIResult) *C.char {
	b, _ := json.Marshal(res)
	return C.CString(string(b))
}

//export GenerateWalletJSON
func GenerateWalletJSON(password *C.char) *C.char {
	account, err := nkn.NewAccount(nil)
	if err != nil {
		return toJSON(FFIResult{Error: err.Error()})
	}
	w, err := nkn.NewWallet(account, &nkn.WalletConfig{Password: C.GoString(password)})
	if err != nil {
		return toJSON(FFIResult{Error: err.Error()})
	}
	walletJSON, err := w.ToJSON()
	if err != nil {
		return toJSON(FFIResult{Error: err.Error()})
	}
	return toJSON(FFIResult{Result: walletJSON})
}

//export GenerateWalletWithSeedJSON
func GenerateWalletWithSeedJSON(seed_hex, password *C.char) *C.char {
	seed, err := hex.DecodeString(C.GoString(seed_hex))
	if err != nil {
		return toJSON(FFIResult{Error: err.Error()})
	}
	account, err := nkn.NewAccount(seed)
	if err != nil {
		return toJSON(FFIResult{Error: err.Error()})
	}
	w, err := nkn.NewWallet(account, &nkn.WalletConfig{Password: C.GoString(password)})
	if err != nil {
		return toJSON(FFIResult{Error: err.Error()})
	}
	walletJSON, err := w.ToJSON()
	if err != nil {
		return toJSON(FFIResult{Error: err.Error()})
	}
	return toJSON(FFIResult{Result: walletJSON})
}

//export CreateNKNClient
func CreateNKNClient(walletJSON, password, identifier *C.char, numSubClients C.int, originalClient C.int) *C.char {
	w, err := nkn.WalletFromJSON(C.GoString(walletJSON), &nkn.WalletConfig{Password: C.GoString(password)})
	if err != nil {
		return toJSON(FFIResult{Error: err.Error()})
	}

	conf := &nkn.ClientConfig{
		MultiClientNumClients:     int(numSubClients),
		MultiClientOriginalClient: originalClient != 0,
	}

	client, err := nkn.NewMultiClientV2(w.Account(), C.GoString(identifier), conf)
	if err != nil {
		return toJSON(FFIResult{Error: err.Error()})
	}

	<-client.OnConnect.C

	addr := client.Address()

	mutex.Lock()
	activeClients[addr] = client
	messageQueues[addr] = make(chan NknMessage, 100)
	mutex.Unlock()

	go func() {
		for msg := range client.OnMessage.C {
			mutex.Lock()
			q, ok := messageQueues[addr]
			mutex.Unlock()
			if ok {
				q <- NknMessage{Src: msg.Src, Data: string(msg.Data)}
			}
		}
	}()

	return toJSON(FFIResult{Result: addr})
}

//export PopNKNMessage
func PopNKNMessage(clientAddr *C.char) *C.char {
	addr := C.GoString(clientAddr)
	mutex.Lock()
	q, ok := messageQueues[addr]
	mutex.Unlock()

	if !ok {
		return toJSON(FFIResult{Error: "client not found"})
	}

	select {
	case msg := <-q:
		return toJSON(FFIResult{Src: msg.Src, Data: msg.Data})
	default:
		return toJSON(FFIResult{})
	}
}

//export SendNKNMessage
func SendNKNMessage(clientAddr, destAddr, message *C.char, maxHoldingSeconds C.int, noReply C.int) *C.char {
	addr := C.GoString(clientAddr)
	dest := C.GoString(destAddr)
	msg := C.GoString(message)

	mutex.Lock()
	client, ok := activeClients[addr]
	mutex.Unlock()

	if !ok {
		return toJSON(FFIResult{Error: "client not found"})
	}

	msgConfig := &nkn.MessageConfig{
		MaxHoldingSeconds: int32(maxHoldingSeconds),
		NoReply:           noReply != 0,
	}

	onMsg, err := client.Send(nkn.NewStringArray(dest), []byte(msg), msgConfig)
	if err != nil {
		return toJSON(FFIResult{Error: "send error: " + err.Error()})
	}

	_ = onMsg
	return toJSON(FFIResult{Result: "success"})
}

//export CloseNKNClient
func CloseNKNClient(clientAddr *C.char) *C.char {
	addr := C.GoString(clientAddr)
	mutex.Lock()
	client, ok := activeClients[addr]
	if ok {
		client.Close()
		delete(activeClients, addr)
		delete(messageQueues, addr)
	}
	mutex.Unlock()

	if !ok {
		return toJSON(FFIResult{Error: "client not found"})
	}
	return toJSON(FFIResult{Result: "success"})
}

//export GetNKNAddress
func GetNKNAddress(walletJSON, password, identifier *C.char) *C.char {
	w, err := nkn.WalletFromJSON(C.GoString(walletJSON), &nkn.WalletConfig{Password: C.GoString(password)})
	if err != nil {
		return toJSON(FFIResult{Error: err.Error()})
	}
	
	pubKey := hex.EncodeToString(w.PubKey())
	var addr string
	if len(C.GoString(identifier)) > 0 {
		addr = C.GoString(identifier) + "." + pubKey
	} else {
		addr = pubKey
	}
	return toJSON(FFIResult{Result: addr})
}

//export FreeNKNString
func FreeNKNString(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func main() {}
