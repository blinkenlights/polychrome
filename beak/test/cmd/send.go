/*
Copyright © 2023 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var address string
var port uint

// sendCmd represents the send command
var sendCmd = &cobra.Command{
	Use:   "send",
	Short: "sends some message",
	Long:  ``,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("don't call send directly use one of the subcommands")
		os.Exit(-1)
	},
}

func init() {
	rootCmd.AddCommand(sendCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	sendCmd.PersistentFlags().StringVarP(&address, "address", "a", "127.0.0.1", "udp address")
	sendCmd.PersistentFlags().UintVarP(&port, "port", "p", 1337, "udp port")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// sendCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
