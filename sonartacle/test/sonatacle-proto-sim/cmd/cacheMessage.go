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

var files []string

// cacheMessageCmd represents the cacheMessage command
var cacheMessageCmd = &cobra.Command{
	Use:   "cacheMessage",
	Short: "A brief description of your command",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
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
		msg := &CacheSamples{
			Uri: files,
		}
		data, err := proto.Marshal(&AudioPacket{
			Content: &AudioPacket_CacheSamples{
				CacheSamples: msg,
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
	sendCmd.AddCommand(cacheMessageCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// cacheMessageCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// cacheMessageCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
	cacheMessageCmd.Flags().StringArrayVarP(&files, "files", "f", []string{"https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/arcade-notification.wav"}, "the file to play")
}
