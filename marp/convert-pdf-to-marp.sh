#!/usr/bin/env zsh

# Convert PDF files to Marp markdown files
# Only converts PDFs where no corresponding .md file exists in the same folder
cd "$(dirname "$(dirname "${(%):-%x}")")"

# Check if PyMuPDF is installed
if ! python3 -c "import fitz" 2>/dev/null; then
  echo "Error: PyMuPDF is not installed."
  echo "Please install it with: pip3 install PyMuPDF"
  exit 1
fi

echo "Searching for PDF files without corresponding Marp markdown files..."

# Find all PDF files
pdf_files=()
found_count=0
while IFS= read -r file; do
  # Check if corresponding .md file exists
  dir=$(dirname "$file")
  basename_no_ext="${$(basename "$file")%.pdf}"
  md_file="$dir/$basename_no_ext.md"
  
  if [[ ! -f "$md_file" ]]; then
    pdf_files+=("$file")
    found_count=$((found_count + 1))
    printf "\rSearching... Found %d PDF files without .md" "$found_count"
  fi
done < <(find . -name node_modules -prune -o -name "*.pdf" -type f -print)

# Sort the files alphabetically
pdf_files=("${(@on)pdf_files}")

total=${#pdf_files[@]}
printf "\rFound %d PDF files without corresponding Marp markdown files.\n\n" "$total"

if [[ $total -eq 0 ]]; then
  echo "No PDF files to convert."
  exit 0
fi

# Process each PDF file
for pdffile in "${pdf_files[@]}"; do
  dir=$(dirname "$pdffile")
  filename=$(basename "$pdffile")
  basename_no_ext="${filename%.pdf}"
  md_file="$dir/$basename_no_ext.md"
  
  echo "Processing: $pdffile"
  
  # Use Python to extract PDF content and create the Marp file directly
  python3 -c "
import sys
import fitz  # PyMuPDF

def extract_and_create_marp(pdf_path, md_path, title):
    \"\"\"Extract text content from PDF and create Marp markdown file.\"\"\"
    try:
        doc = fitz.open(pdf_path)
        
        # Create Marp file with header
        with open(md_path, 'w', encoding='utf-8') as f:
            # Write Marp header
            f.write('''---
marp: true
theme: oblicum-marp-theme
footer: \"![](../../marp/glasspaper-logo.svg) ![](../../marp/oblicum-logo.svg)\"
---

<!-- _class: lead -->

# ''' + title + '''

## <subtitle>

#### Rick Beerendonk<br>rick@oblicum.com

---

''')
            
            # Extract and write content from each page
            for page_num in range(len(doc)):
                page = doc[page_num]
                
                # Skip first page (title page)
                if page_num == 0:
                    continue
                
                # Get text blocks with formatting info
                blocks = page.get_text('dict')['blocks']
                
                slide_title = ''
                content_parts = []
                
                for block in blocks:
                    if 'lines' not in block:
                        continue
                    
                    for line in block['lines']:
                        line_text = ''
                        max_size = 0
                        
                        for span in line['spans']:
                            text = span['text']
                            size = span['size']
                            line_text += text
                            max_size = max(max_size, size)
                        
                        line_text = line_text.strip()
                        if not line_text:
                            continue
                        
                        # Large font size = title (typically > 50)
                        if max_size > 50:
                            slide_title = line_text
                        else:
                            content_parts.append(line_text)
                
                # Write slide
                if slide_title:
                    f.write(f'## {slide_title}\n\n')
                
                if content_parts:
                    f.write('\n'.join(content_parts))
                    f.write('\n\n')
                
                f.write('---\n\n')
        
        doc.close()
        return True
    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
        import traceback
        traceback.print_exc()
        return False

pdf_path = sys.argv[1]
md_path = sys.argv[2]
title = sys.argv[3]

if extract_and_create_marp(pdf_path, md_path, title):
    print(f'  ✓ Created: {md_path}')
else:
    print(f'  ✗ Failed to process {pdf_path}', file=sys.stderr)
    sys.exit(1)
" "$pdffile" "$md_file" "$basename_no_ext"

  echo ""
done

echo "Conversion complete! Created $total markdown files with extracted PDF content."
echo ""
echo "Next steps:"
echo "1. Review each created .md file"
echo "2. Adjust formatting and slide breaks as needed"
echo "3. Customize the Marp frontmatter as needed"
