#!/bin/bash
# Extract text from .rtf files using macOS textutil
textutil -convert txt -stdout "$1"
