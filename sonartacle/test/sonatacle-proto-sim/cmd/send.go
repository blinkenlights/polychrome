/*
Copyright © 2023 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

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
	sendCmd.PersistentFlags().StringP("address", "a", "127.0.0.1", "udp address")
	sendCmd.PersistentFlags().IntP("port", "p", 60000, "udp port")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// sendCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
