/*
Copyright © 2023 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"fmt"
	"net"
	"os"

	"google.golang.org/protobuf/proto"

	"github.com/spf13/cobra"
)

var file string
var channel uint32

// playMessageCmd represents the playMessage command
var playMessageCmd = &cobra.Command{
	Use:   "playMessage",
	Short: "Sends a play message",
	Long:  ``,
	RunE: func(cmd *cobra.Command, args []string) error {
		endpoint := fmt.Sprintf("%s:%d", address, port)
		fmt.Println(endpoint)
		// Resolve the string address to a UDP address
		udpAddr, err := net.ResolveUDPAddr("udp", endpoint)

		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}

		// Dial to the address with UDP
		conn, err := net.DialUDP("udp", nil, udpAddr)

		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}

		// Send a message to the server
		msg := &AudioFrame{
			Uri:     file,
			Channel: channel,
		}
		data, err := proto.Marshal(&Packet{
			Content: &Packet_AudioFrame{
				AudioFrame: msg,
			},
		})

		if err != nil {
			return err
		}
		_, err = conn.Write(data)
		fmt.Println("send...")
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}
		return nil
	},
}

func init() {
	sendCmd.AddCommand(playMessageCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// playMessageCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	playMessageCmd.Flags().StringVarP(&file, "file", "f", "/Users/lukas/dev/letterbox/sonartacle/resources/pew.wav", "the file to play")
	playMessageCmd.Flags().Uint32VarP(&channel, "channel", "c", 1, "the channel to play the sample on")
}
