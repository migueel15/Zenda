package main

import (
	"encoding/json"
	"fmt"

	"github.com/migueel15/Zenda/core/internal/battery"
	"github.com/spf13/cobra"
)

func batteryCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "battery",
		Short: "Consultar baterías de dispositivos",
	}

	cmd.AddCommand(&cobra.Command{
		Use:          "list",
		Short:        "Listar baterías de dispositivos HID++ en JSON",
		Args:         cobra.NoArgs,
		SilenceUsage: true,
		RunE: func(_ *cobra.Command, _ []string) error {
			devices := battery.ListHIDPP()
			out, err := json.Marshal(devices)
			if err != nil {
				return err
			}
			fmt.Println(string(out))
			return nil
		},
	})

	return cmd
}
