#!/bin/bash
# Extract text from .docx files using macOS textutil
textutil -convert txt -stdout "$1"
