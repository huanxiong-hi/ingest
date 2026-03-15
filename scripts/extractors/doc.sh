#!/bin/bash
# Extract text from .doc / .docx files using macOS textutil
textutil -convert txt -stdout "$1"
