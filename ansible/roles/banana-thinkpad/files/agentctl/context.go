package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

func (r *Run) copyContext() error {
	dir := r.path("context")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	files := append([]string{r.Spec.Context.Prompt}, r.Spec.Context.Knowledge...)
	for _, src := range files {
		dst := filepath.Join(dir, filepath.Base(src))
		if err := copyFile(src, dst); err != nil {
			return fmt.Errorf("copy %s: %w", src, err)
		}
	}
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}
