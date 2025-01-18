package main

import (
	"archive/tar"
	"debug/elf"
	"io"
	"log"
	"os"
	"os/exec"
	"path"
	"strings"

	"github.com/go-faster/errors"
	"github.com/klauspost/compress/zstd"
)

func main() {
	if err := start(); err != nil {
		log.Fatal(err)
	}
}

func start() error {
	dir, err := os.MkdirTemp("", "statish")
	if err != nil {
		return errors.Wrap(err, "failed to create temporary directory")
	}
	defer os.RemoveAll(dir)

	if err := os.Setenv("PATH", dir+":"+os.Getenv("PATH")); err != nil {
		return errors.Wrap(err, "failed to set PATH")
	}

	cmd, err := unpack(dir)
	if err != nil {
		return err
	}

	if err := cmd.Run(); err != nil {
		return errors.Wrap(err, "child process failed")
	}

	return nil
}

func unpack(dir string) (*exec.Cmd, error) {
	self, err := os.Open("/proc/self/exe")
	if err != nil {
		return nil, errors.Wrap(err, "could not open self")
	}
	defer self.Close()

	file, err := elf.NewFile(self)
	if err != nil {
		return nil, errors.Wrap(err, "could not parse self as ELF executable")
	}
	defer file.Close()

	section := file.Section("statish")
	if section == nil {
		return nil, errors.New("self has no `statish` section")
	}

	reader := section.Open()

	decomp, err := zstd.NewReader(reader)
	if err != nil {
		return nil, errors.Wrap(err, "failed to construct zstd decompressor")
	}
	defer decomp.Close()

	unpack := tar.NewReader(decomp)

	for {
		header, err := unpack.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, errors.Wrap(err, "failed to read from archive")
		}

		info := header.FileInfo()
		if info.IsDir() {
			continue
		}

		outpath := path.Join(dir, header.Name)
		os.MkdirAll(path.Dir(outpath), 0755)

		if header.Linkname != "" {
			if err := os.Symlink(header.Linkname, outpath); err != nil {
				return nil, errors.Wrapf(err, "failed to create symlink `%v` -> `%v`", outpath, header.Linkname)
			}
			continue
		}

		out, err := os.Create(outpath)
		if err != nil {
			return nil, errors.Wrapf(err, "failed to create file %v", outpath)
		}
		defer out.Close()

		if err := os.Chmod(outpath, info.Mode()); err != nil {
			return nil, errors.Wrapf(err, "failed to set `%v` to mode `%v`", outpath, info.Mode())
		}

		if _, err := io.Copy(out, unpack); err != nil {
			return nil, errors.Wrapf(err, "failed to write to file %v", outpath)
		}
	}

	main := path.Join(dir, "main")
	cmd := &exec.Cmd{
		Path:   main,
		Args:   append([]string{main}, os.Args[1:]...),
		Stdin:  os.Stdin,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}

	section = file.Section("statish-shell")
	if section != nil {
		shellRaw, err := io.ReadAll(section.Open())
		if err != nil {
			return nil, errors.Wrap(err, "failed to read shell name")
		}

		shell := path.Join(dir, strings.TrimSpace(string(shellRaw)))
		cmd.Path = shell
		cmd.Args = append([]string{shell}, cmd.Args...)
	}

	return cmd, nil
}
