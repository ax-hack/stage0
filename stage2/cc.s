; Copyright (C) 2016 Jeremiah Orians
; This file is part of stage0.
;
; stage0 is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; stage0 is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with stage0.  If not, see <http://www.gnu.org/licenses/>.

;; A Minimal C Compiler
;; type Cells are in the following form:
;; NEXT (0), SIZE (4), OFFSET (8), INDIRECT (12), MEMBERS (16), TYPE (20), NAME (24)
;; token_list Cells are in the following form:
;; NEXT (0), LOCALS/PREV (4), S (8), TYPE/FILENAME (12), ARGUMENTS/DEPTH/LINENUMBER (16)
;; Each being the length of a register [32bits]
;;

;; STACK space: End of program -> 1MB (0x100000)
;; HEAP space: 1MB -> End of Memory (2MB (0x200000))

;; R15 is the STACK pointer
;; R14 is the HEAP pointer

:start
	;; Prep TAPE_02
	LOADUI R0 0x1101
	FOPEN_WRITE

	;; Prep TAPE_01
	LOADUI R0 0x1100
	FOPEN_READ

:main
	LOADUI R0 0x1100            ; Pass Tape_01 for reading
	LOADR32 R14 @HEAP           ; Setup Initial HEAP
	LOADUI R15 $STACK           ; Setup Initial STACK
	CALLI R15 @read_all_tokens  ; Read all Tokens in Tape_01
	CALLI R15 @reverse_list     ; Fix Token Order
;	CALLI R15 @debug_list       ; Lets try to debug token errors
	MOVE R13 R0                 ; Set global_token for future reading
	FALSE R12                   ; Set struct token_list* out to NULL
	FALSE R11                   ; Set struct token_list* list_strings to NULL
	FALSE R10                   ; Set struct token_list* globals_list to NULL
	CALLI R15 @program          ; Build our output
	LOADUI R0 $header_string1   ; Using our first header string
	LOADUI R1 0x1101            ; Using Tape_02
	CALLI R15 @file_print       ; Write string
	MOVE R0 R12                 ; using Contents of output_list
	CALLI R15 @recursive_output ; Recursively write
	LOADUI R0 $header_string2   ; Using our second header string
	CALLI R15 @file_print       ; Write string
	MOVE R0 R10                 ; using Contents of globals_list
	CALLI R15 @recursive_output ; Recursively write
	LOADUI R0 $header_string3   ; Using our third header string
	CALLI R15 @file_print       ; Write string
	MOVE R0 R11                 ; using Contents of strings_list
	CALLI R15 @recursive_output ; Recursively write
	LOADUI R0 $header_string4   ; Using our fourth header string
	CALLI R15 @file_print       ; Write string
	HALT                        ; We have completed compiling our input

;; Symbol lists
:global_constant_list
	NOP
:global_symbol_list
	NOP
:global_function_list
	NOP

;; Pointer to initial HEAP ADDRESS
:HEAP
	'00180000'

;; Output strings
:header_string1
	"
# Core program
"
:header_string2
	"
# Program global variables
"

:header_string3
	"
# Program strings
"

:header_string4
	"
:ELF_end
"


;; clearWhiteSpace function
;; Recieves a character in R0 and FILE* in R1 and line_num in R11
;; Returns first non-whitespace character in R0
:clearWhiteSpace
	CMPSKIPI.NE R0 32           ; Check for a Space
	JUMP @clearWhiteSpace_reset ; Looks like we need to remove a space

	CMPSKIPI.NE R0 9            ; Check for a tab
	JUMP @clearWhiteSpace_reset ; Looks like we need to remove a tab

	CMPSKIPI.E R0 10            ; Check for a newline
	RET R15                     ; Looks we found a non-whitespace

	ADDUI R11 R11 1             ; Increment line number
	;; Fall through to iterate to next char

:clearWhiteSpace_reset
	FGETC                       ; Get next char
	JUMP @clearWhiteSpace       ; Iterate


;; consume_byte function
;; Recieves a char in R0, FILE* in R1 and index in R13
;; Returns next char in R0
:consume_byte
	STOREX8 R0 R14 R13          ; Put char onto HEAP
	ADDUI R13 R13 1             ; Increment index
	FGETC                       ; Get next char
	RET R15


;; consume_word function
;; Recieves a char in R0, FILE* in R1, FREQUENT in R2 and index in R13
;; Returns next char in R0
:consume_word
	PUSHR R3 R15                ; Protect R3
	FALSE R3                    ; ESCAPE is FALSE
:consume_word_reset
	JUMP.NZ R3 @consume_word_iter1
	CMPSKIPI.NE R0 47           ; If \
	TRUE R3                     ; Looks like we are in an escape
	JUMP @consume_word_iter2
:consume_word_iter1
	FALSE R3                    ; Looks like we are no longer in an escape
:consume_word_iter2
	CALLI R15 @consume_byte     ; Store the char
	JUMP.NZ R3 @consume_word_reset        ; If escape loop
	CMPJUMPI.NE R0 R2 @consume_word_reset ; if not matching frequent loop
	FGETC                       ; Get a new char to return
	POPR R3 R15                 ; Restore R3
	RET R15


;; fixup_label function
;; Recieves nothing (But uses R14 as HEAP pointer)
;; Returns 32 in R0 and no other registers altered
:fixup_label
	PUSHR R1 R15                ; Protect R1 from change
	PUSHR R2 R15                ; Protect R2 from change
	LOADUI R0 58                ; Set HOLD to :
	FALSE R2                    ; Set I to 0
:fixup_label_reset
	MOVE R1 R0                  ; Set PREV = HOLD
	LOADXU8 R0 R14 R2           ; Read hold_string[I] into HOLD
	STOREX8 R1 R14 R2           ; Set hold_string[I] = PREV
	ADDUI R2 R2 1               ; increment I
	JUMP.NZ R0 @fixup_label_reset ; Loop until we hit a NULL

	;; clean up
	ADDUI R2 R2 1               ; increment I
	LOADUI R0 32                ; Put 32 in R0
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	RET R15


;; in_set2 function
;; Recieves a Char in R0, FILE* in R1, char* in R2 and index in R13
;; Return result in R2
:in_set2
	PUSHR R3 R15                ; Protect R3 from changes
:in_set2_reset
	LOADU8 R3 R2 0              ; Get char from list
	CMPJUMPI.E R0 R3 @in_set2_done ; We found a match
	ADDUI R2 R2 1               ; Increment to next char
	JUMP.NZ R3 @in_set2_reset   ; Iterate if not NULL

	;; Looks like not found
	FALSE R2                    ; Return FALSE

:in_set2_done
	CMPSKIPI.E R2 0             ; Provided not FALSE
	TRUE R2                     ; The result is true
	POPR R3 R15                 ; Restore R3
	RET R15


;; in_set function
;; Recieves a Char in R0, char* in R1
;; Return result in R0
:in_set
	PUSHR R2 R15                ; Protect R3 from changes
:in_set_reset
	LOADU8 R2 R1 0              ; Get char from list
	CMPJUMPI.E R0 R2 @in_set_done ; We found a match
	ADDUI R1 R1 1               ; Increment to next char
	JUMP.NZ R2 @in_set_reset    ; Iterate if not NULL

	;; Looks like not found
	FALSE R1                    ; Return FALSE

:in_set_done
	CMPSKIPI.E R1 0             ; Provided not FALSE
	TRUE R2                     ; The result is true
	MOVE R0 R2                  ; Put result in correct place
	POPR R2 R15                 ; Restore R3
	RET R15

;; Common in_set strings of interest
;; As Raw strings (") is forbidden and ' has some restrictions
:nice_chars
	"	
 !#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
:keyword_chars
	"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
:symbol_chars
	"<=>|&!-"
:hex_chars
	"0123456789ABCDEF"
:digit_chars
	"0123456789"
:whitespace_chars
	" 	
"

;; preserve_keyword function
;; Recieves a Char in R0, FILE* in R1 and index in R13
;; Overwrites R2
;; Returns next CHAR
:preserve_keyword
	LOADUI R2 $keyword_chars    ; Using keyword list of chars
	CALLI R15 @in_set2          ; Check if in list
	JUMP.Z R2 @preserve_keyword_label ; if not in set, stop iterating

:preserve_keyword_reset
	CALLI R15 @consume_byte     ; Consume another byte
	JUMP @preserve_keyword      ; Iterate

:preserve_keyword_label
	CMPSKIPI.NE R0 58           ; Check for label (:)
	CALLI R15 @fixup_label      ; Looks like we found one
	RET R15


;; preserve_symbol function
;; Recieves a Char in R0, FILE* in R1 and index in R13
;; Overwrites R2
;; Returns next CHAR
:preserve_symbol
	LOADUI R2 $symbol_chars     ; Using symbol list of chars
	CALLI R15 @in_set2          ; Check if in list
	JUMP.NZ R2 @preserve_symbol_reset

	;; Looks we didn't find anything we wanted to preserve
	RET R15

:preserve_symbol_reset
	CALLI R15 @consume_byte     ; Consume another byte
	JUMP @preserve_symbol       ; Iterate


;; purge_macro function
;; Recieves a Char in R0, FILE* in R1 and index in R13
;; Returns next CHAR via jumping to get_token_reset
:purge_macro
	CMPSKIPI.NE R0 10           ; Check for Line Feed
	JUMP @get_token_reset       ; Looks like we found it, call it done

	FGETC                       ; Looks like we need another CHAR
	JUMP @purge_macro           ; Keep looping


;; get_token function
;; Recieves a Char in R0, FILE* in R1, line_num in R11 and TOKEN in R10
;; sets index in R13 and current in R12
;; Overwrites R2
;; Returns next CHAR
:get_token
	PUSHR R12 R15               ; Preserve R12
	PUSHR R13 R15               ; Preserve R13
	COPY R12 R14                ; Save CURRENT's Address
	ADDUI R14 R14 20            ; Update Malloc to free space for string
:get_token_reset
	FALSE R13                   ; Reset string_index to 0
	CALLI R15 @clearWhiteSpace  ; Clear any leading whitespace
	CMPSKIPI.NE R0 35           ; Deal with # line macros
	JUMP @purge_macro           ; Returns at get_token_reset

	;; Check for keywords
	LOADUI R2 $keyword_chars    ; Using keyword list
	CALLI R15 @in_set2          ; Check if keyword
	JUMP.Z R2 @get_token_symbol ; if not a keyword
	CALLI R15 @preserve_keyword ; Yep its a keyword
	JUMP @get_token_done        ; Be done with token

	;; Check for symbols
:get_token_symbol
	LOADUI R2 $symbol_chars     ; Using symbol list
	CALLI R15 @in_set2          ; Check if symbol
	JUMP.Z R2 @get_token_char   ; If not a symbol
	CALLI R15 @preserve_symbol  ; Yep its a symbol
	JUMP @get_token_done        ; Be done with token

	;; Check for char
:get_token_char
	CMPSKIPI.E R0 39            ; Check if '
	JUMP @get_token_string      ; Not a '
	COPY R2 R0                  ; Prepare for consume_word
	CALLI R15 @consume_word     ; Call it
	JUMP @get_token_done        ; Be done with token

	;; Check for string
:get_token_string
	CMPSKIPI.E R0 34            ; Check if "
	JUMP @get_token_EOF         ; Not a "
	COPY R2 R0                  ; Prepare for consume_word
	CALLI R15 @consume_word     ; Call it
	JUMP @get_token_done        ; Be done with token

	;; Check for EOF
:get_token_EOF
	CMPSKIPI.L R0 0             ; If c < 0
	JUMP @get_token_comment     ; If not EOF
	POPR R13 R15                ; Restore R13
	POPR R12 R15                ; Restore R12
	RET R15                     ; Otherwise just return the EOF

	;; Check for C comments
:get_token_comment
	CMPSKIPI.E R0 47            ; Deal with non-comments
	JUMP @get_token_else        ; immediately

	CALLI R15 @consume_byte     ; Deal with another byte
	CMPSKIPI.NE R0 42           ; if * make it a block comment
	JUMP @get_token_comment_block ; and purge it all

	CMPSKIPI.E R0 47            ; Check if not //
	JUMP @get_token_done        ; Finish off the token

	;; Looks like it was //
	FGETC                       ; Get next char
	JUMP @get_token_reset       ; Try again

	;; Deal with the mess that is C block comments
:get_token_comment_block
	FGETC                       ; Get next char
:get_token_comment_block_outer
	CMPSKIPI.NE R0 47           ; Check for closing /
	JUMP @get_token_comment_block_outer_done ; Yep has closing /
:get_token_comment_block_inner
	CMPSKIPI.NE R0 42           ; Check for preclosing *
	JUMP @get_token_comment_block_inner_done ; Yep has *

	;; Otherwise we are just consuming
	FGETC                       ; Remove another CHAR
	CMPSKIPI.NE R0 10           ; Check for Line Feed
	ADDUI R11 R11 1             ; Found one, updating line number
	JUMP @get_token_comment_block_inner

:get_token_comment_block_inner_done
	FGETC                       ; Remove another CHAR
	CMPSKIPI.NE R0 10           ; Check for Line Feed
	ADDUI R11 R11 1             ; Found one, updating line number
	JUMP @get_token_comment_block_outer

:get_token_comment_block_outer_done
	FGETC                       ; Remove another CHAR
	JUMP @get_token_reset       ; And Try again

	;; Deal with default case
:get_token_else
	CALLI R15 @consume_byte     ; Consume the byte and be done

:get_token_done
	ADDUI R13 R13 2             ; Pad with NULL the string
	STORE32 R14 R12 8           ; Set CURRENT->S to String
	ADD R14 R14 R13             ; Add string length to HEAP

	STORE32 R10 R12 0           ; CURRENT->NEXT = TOKEN
	STORE32 R10 R12 4           ; CURRENT->PREV = TOKE
	STORE32 R11 R12 16          ; CURRENT->LINENUM = LINE_NUM
	MOVE R10 R12                ; SET TOKEN to CURRENT
	POPR R13 R15                ; Restore R13
	POPR R12 R15                ; Restore R12
	RET R15


;; reverse_list function
;; Recieves a Token_list in R0
;; Returns List in Reverse order in R0
:reverse_list
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	FALSE R1                    ; Set ROOT to NULL
	CMPJUMPI.E R0 R1 @reverse_list_done ; ABORT if given a NULL
:reverse_list_reset
	LOAD32 R2 R0 0              ; SET next to HEAD->NEXT
	STORE32 R1 R0 0             ; SET HEAD->NEXT to ROOT
	MOVE R1 R0                  ; SET ROOT to HEAD
	MOVE R0 R2                  ; SET HEAD to NEXT
	JUMP.NZ R0 @reverse_list_reset ; Iterate if HEAD not NULL

:reverse_list_done
	MOVE R0 R1                  ; SET Result to ROOT
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	RET R15


;; read_all_tokens function
;; Recieves a FILE* in R0
;; sets line_num in R11 and TOKEN in R10
;; Overwrites R2
;; Returns struct token_list* in R0
:read_all_tokens
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	PUSHR R10 R15               ; Protect R10
	PUSHR R11 R15               ; Protect R11
	MOVE R1 R0                  ; Set R1 as FILE*
	FGETC                       ; Read our first CHAR
	LOADUI R11 1                ; Start line_num at 1
	FALSE R10                   ; First token is NULL
:read_all_tokens_reset
	JUMP.NP R0 @read_all_tokens_done
	CALLI R15 @get_token
	JUMP @read_all_tokens_reset
:read_all_tokens_done
	MOVE R0 R10                 ; Return the Token
	POPR R11 R15                ; Restore R11
	POPR R10 R15                ; Restore R10
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	RET R15


;; parse_string function
;; Recieves char* string in R0
;; R14 is HEAP Pointer
;; Returns char* in R0
:parse_string
	PUSHR R1 R15                ; Protect R1
	COPY R1 R0                  ; Make a copy of STRING
	CALLI R15 @weird            ; Check if string is weird
	SWAP R0 R1
	JUMP.Z R1 @parse_string_regular ; Deal with regular strings

	;; Looks like we have a weirdo
	CALLI R15 @collect_weird_string ; Create our weird string
	JUMP @parse_string_done     ; Simply return what was created
:parse_string_regular
	CALLI R15 @collect_regular_string
:parse_string_done
	POPR R1 R15                 ; Restore R1
	RET R15


;; weird function
;; Analyze string to determine if it's output would be weird for mescc-tools
;; Recieves char* in R0
;; Returns BOOL in R0
:weird
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	PUSHR R3 R15                ; Protect R3
	PUSHR R4 R15                ; Protect R4
	FALSE R2                    ; Assume FALSE
	ADDUI R3 R0 1               ; STRING = STRING + 1
:weird_iter
	JUMP.NZ R2 @weird_done      ; Stop if TRUE
	LOADU8 R4 R3 0              ; C = STRING[0]
	JUMP.Z R4 @weird_done       ; Be done at NULL Termination
	CMPSKIPI.E R4 92            ; If not '\\'
	JUMP @weird_post_escape     ; Looks like no escape analysis

	;; Deal with the mess
	COPY R0 R3                  ; Using STRING
	CALLI R15 @escape_lookup    ; Get our CHAR
	MOVE R4 R0                  ; C = ESCAPE_LOOKUP(STRING)
	LOADU8 R0 R3 1              ; STRING[1]
	CMPSKIPI.NE R0 120          ; if 'x' == STRING[1]
	ADDUI R3 R3 2               ; STRING = STRING + 2
	ADDUI R3 R3 1               ; STRING = STRING + 1

:weird_post_escape
	LOADUI R1 $nice_chars       ; using list of nice CHARS
	COPY R0 R4                  ; using copy of C
	CALLI R15 @in_set           ; Use in_set
	NOT R0 R0                   ; Reverse bool
	CMPSKIPI.E R0 0             ; IF TRUE
	TRUE R2                     ; Return TRUE
	ADDUI R3 R3 1               ; STRING = STRING + 1
	LOADUI R1 $whitespace_chars ; Check Whitespace Chars
	COPY R0 R4                  ; Using copy of C
	CALLI R15 @in_set           ; Use in_set
	JUMP.Z R0 @weird_iter       ; If False simply loop
	LOADU8 R0 R3 0              ; STRING[1]
	CMPSKIPI.NE R0 58           ; If ':' == STRING[1]
	TRUE R2                     ; Flip flag
	JUMP @weird_iter            ; Keep trying to find an answer

:weird_done
	MOVE R0 R2                  ; Whatever is in R2 is the answer
	POPR R4 R15                 ; Restore R4
	POPR R3 R15                 ; Restore R3
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	RET R15


;; collect_weird_string function
;; Converts weird string into a form mescc-tools can handle cleanly
;; Recieves char* in R0
;; R14 is HEAP Pointer and $hex_chars as the table
;; Returns char* in R0
:collect_weird_string
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	PUSHR R3 R15                ; Protect R3
	PUSHR R4 R15                ; Protect R4
	LOADUI R4 $hex_chars        ; Pointer to TABLE
	COPY R3 R14                 ; Get HOLD
	MOVE R2 R0                  ; Put STRING in Place
	LOADUI R0 39                ; Prefix with '
	PUSH8 R0 R3                 ; HOLD[0] = '\'' && HOLD = HOLD + 1
:collect_weird_string_iter
	ADDUI R2 R2 1               ; STRING = STRING + 1
	LOADUI R0 32                ; Insert ' '
	PUSH8 R0 R3                 ; HOLD[0] = ' ' && HOLD = HOLD + 1
	COPY R0 R2                  ; copy STRING
	CALLI R15 @escape_lookup    ; Get char value
	ANDI R1 R0 0x0F             ; Save Bottom out of the way
	SR0I R0 4                   ; Isolate Top
	LOADXU8 R0 R4 R0            ; Using Table
	LOADXU8 R1 R4 R1            ; Using Table
	PUSH8 R0 R3                 ; HOLD[0] = TABLE[(TEMP >> 4)] && HOLD = HOLD + 1
	PUSH8 R1 R3                 ; HOLD[0] = TABLE[(TEMP & 15)] && HOLD = HOLD + 1
	LOADU8 R0 R2 0              ; STRING[0]
	JUMP.Z R0 @collect_weird_string_done ; Stop if NULL
	CMPSKIPI.E R0 92            ; IF STRING[0] != '\\'
	JUMP @collect_weird_string_iter ; Just loop
	LOADU8 R0 R2 1              ; STRING[1]
	CMPSKIPI.NE R0 120          ; If STRING[1] == 'x'
	ADDUI R2 R2 2               ; STRING = STRING + 2
	ADDUI R2 R2 1               ; STRING = STRING + 1
	JUMP @collect_weird_string_iter

:collect_weird_string_done
	LOADUI R0 32                ; Insert ' '
	PUSH8 R0 R3                 ; HOLD[0] = ' ' && HOLD = HOLD + 1
	LOADUI R0 48                ; Insert '0'
	PUSH8 R0 R3                 ; HOLD[0] = '0' && HOLD = HOLD + 1
	LOADUI R0 48                ; Insert '0'
	PUSH8 R0 R3                 ; HOLD[0] = '0' && HOLD = HOLD + 1
	LOADUI R0 39                ; Insert '\''
	PUSH8 R0 R3                 ; HOLD[0] = '\'' && HOLD = HOLD + 1
	LOADUI R0 10                ; Insert '\n'
	PUSH8 R0 R3                 ; HOLD[0] = '\n' && HOLD = HOLD + 1
	ADDUI R3 R3 1               ; NULL Terminate
	SWAP R3 R14                 ; CALLOC HOLD
	MOVE R0 R3                  ; Return HOLD
	POPR R4 R15                 ; Restore R4
	POPR R3 R15                 ; Restore R3
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	RET R15


;; hex function
;; Recieves Char in R0
;; Return Int in R0
:hex
	SUBUI R0 R0 48              ; First shift
	CMPSKIPI.GE R0 10           ; If 0-9
	RET R15                     ; Be done

	;; Deal with A-F
	ANDI R0 R0 0xDF             ; Unset high bit
	SUBUI R0 R0 7               ; Shift them down
	CMPSKIPI.GE R0 10           ; if between 9 and A
	JUMP @hex_error             ; Throw an error
	CMPSKIPI.L R0 16            ; if > F
	JUMP @hex_error             ; Throw an error
	RET R15

:hex_error
	LOADUI R0 $hex_error_message ; Our message
	FALSE R1                    ; For human
	CALLI R15 @file_print       ; write it
	CALLI R15 @line_error       ; More info
	HALT

:hex_error_message
	"Tried to print non-hex number
"


;; escape_lookup function
;; Recieves char* in R0
;; Returns char in R0
:escape_lookup
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	MOVE R1 R0                  ; Put C in the right spot
	FALSE R2                    ; Our flag for done
	LOADU8 R0 R1 0              ; c[0]
	CMPSKIPI.E R0 92            ; If C[0] != '\\'
	JUMP @escape_lookup_none    ; Deal with none case

	LOADU8 R0 R1 1              ; c[1]
	CMPSKIPI.NE R0 120          ; if \x??
	JUMP @escape_lookup_hex

	;; Deal with \? escapes
	CMPSKIPI.NE R0 110          ; If \n
	LOADUI R2 10                ; return \n

	CMPSKIPI.NE R0 116          ; If \t
	LOADUI R2 9                 ; return \t

	CMPSKIPI.NE R0 92           ; If \\
	LOADUI R2 92                ; return \\

	CMPSKIPI.NE R0 39           ; If \'
	LOADUI R2 39                ; return \'

	CMPSKIPI.NE R0 34           ; If \"
	LOADUI R2 34                ; return \"

	CMPSKIPI.NE R0 114          ; If \r
	LOADUI R2 13                ; return \r

	JUMP.Z R2 @escape_lookup_error ; Looks like we got something weird
	JUMP @escape_lookup_done    ; Otherwise just use our R2

:escape_lookup_none
	MOVE R2 R0                  ; We just return the char at C[0]
	JUMP @escape_lookup_done    ; Be done

:escape_lookup_hex
	LOADU8 R0 R1 2              ; c[2]
	CALLI R15 @hex              ; Get first char
	SL0I R0 4                   ; Shift our first nybble
	MOVE R2 R0                  ; Protect our top nybble
	LOADU8 R0 R1 3              ; c[3]
	CALLI R15 @hex              ; Get second char
	ADD R2 R2 R0                ; \x?? => ? << 4 + ?

:escape_lookup_done
	MOVE R0 R2                  ; R2 has our answer
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	RET R15

:escape_lookup_error
	MOVE R2 R0                  ; Protect Char that failed
	LOADUI R0 $escape_lookup_string0 ; Load message
	FALSE R1                    ; We want the User to see
	CALLI R15 @file_print       ; Write it
	MOVE R0 R2                  ; Our CHAR
	FPUTC                       ; Write it
	LOADUI R0 10                ; '\n'
	FPUTC                       ; Write it
	CALLI R15 @line_error       ; Provide some debug information
	HALT

:escape_lookup_string0
	"Recieved invalid escape \\"


;; collect_regular_string function
;; Converts C string into a RAW string for mescc-tools
;; Recieves char* in R0
;; R14 is HEAP Pointer
;; Returns char* in R0
:collect_regular_string
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	COPY R2 R14                 ; MESSAGE
	MOVE R1 R0                  ; Put STRING in the right place
:collect_regular_string_iter
	LOADU8 R0 R1 0              ; STRING[0]
	JUMP.Z R0 @collect_regular_string_done ; End at NULL
	CMPSKIPI.NE R0 92           ; if STRING[0] == '\\'
	JUMP @collect_regular_string_escape ; deal with escapes

	;; Deal with vannilla chars
	STORE8 R0 R2 0              ; MESSAGE[0] = STRING[0]
	ADDUI R2 R2 1               ; MESSAGE = MESSAGE + 1
	ADDUI R1 R1 1               ; STRING = STRING + 1
	JUMP @collect_regular_string_iter ; Loop

:collect_regular_string_escape
	COPY R0 R1                  ; Prepare for call
	CALLI R15 @escape_lookup    ; Get what weird char we need
	STORE8 R0 R2 0              ; MESSAGE[0] = escape_lookup(string)
	ADDUI R2 R2 1               ; MESSAGE = MESSAGE + 1
	LOADU8 R0 R1 1              ; STRING[1]
	CMPSKIPI.NE R0 120          ; if \x??
	ADDUI R1 R1 2               ; STRING = STRING + 2
	ADDUI R1 R1 2               ; STRING = STRING + 2
	JUMP @collect_regular_string_iter ; Loop

:collect_regular_string_done
	LOADUI R0 34                ; Using "
	STORE8 R0 R2 0              ; MESSAGE[0] = '"'
	LOADUI R0 10                ; Using '\n'
	STORE8 R0 R2 1              ; MESSAGE[1] = "\n"
	ADDUI R2 R2 3               ; Add extra NULL padding
	SWAP R2 R14                 ; Update HEAP
	MOVE R0 R2                  ; Put MESSAGE in the right Spot
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	RET R15


	
	
	
;; recursive_statement function
;; Recieves struct token_list* global_token in R13,
;;	struct token_list* out in R12,
;;	struct token_list* string_list in R11
;;	struct token_list* global_list in R10
;;	and struct token_list* FUNC in R9
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns the token_lists modified
:recursive_statement
	PUSHR R0 R15                ; Protect R0
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	PUSHR R3 R15                ; Protect R3
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	LOAD32 R3 R9 4              ; FRAME = FUNCTION->LOCALS
:recursive_statement_iter
	LOAD32 R1 R13 8             ; GLOBAL_TOKEN->S
	LOADUI R0 $close_curly_brace ; '}'
	CALLI R15 @match            ; IF GLOBAL_TOKEN->S == "}"
	JUMP.NZ R0 @recursive_statement_cleanup

	;; Lets collect those statements
	CALLI R15 @statement        ; Collect next statement
	JUMP @recursive_statement_iter ; Iterate

:recursive_statement_cleanup
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	LOAD32 R1 R12 8             ; OUT->S
	LOADUI R0 $recursive_statement_string0 ; "RETURN\n"
	CALLI R15 @match            ; IF OUT->S == "RETURN\n"
	JUMP.NZ R0 @recursive_statement_done ; Save some work

	;; Lets pop them all off
	LOAD32 R2 R9 4              ; FUNC->LOCALS
:recursive_statement_pop
	CMPJUMPI.E R2 R3 @recursive_statement_done
	LOADUI R0 $recursive_statement_string1 ; Our POP string
	COPY R1 R12                 ; Using OUT
	CALLI R15 @emit             ; emit it
	MOVE R12 R0                 ; Update OUT
	LOAD32 R2 R2 0              ; I = I->NEXT
	JUMP.NZ R2 @recursive_statement_pop ; Keep looping

:recursive_statement_done
	STORE32 R2 R9 4             ; FUNC->LOCALS = FRAME
	POPR R3 R15                 ; Restore R3
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	POPR R0 R15                 ; Restore R0
	RET R15

:recursive_statement_string0
	"RETURN
"
:recursive_statement_string1
	"POP_ebx	# _recursive_statement_locals
"



;; statement function
;; Recieves struct token_list* global_token in R13,
;;	struct token_list* out in R12,
;;	struct token_list* string_list in R11
;;	struct token_list* global_list in R10
;;	and struct token_list* FUNC in R9
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns the token_lists modified
:statement
	PUSHR R0 R15                ; Protect R0
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	LOAD32 R2 R13 8             ; GLOBAL_TOKEN->S
	LOADU8 R0 R2 0              ; GLOBAL_TOKEN->S[0]
	CMPSKIPI.E R0 123           ; If GLOBAL_TOKEN->S[0] != '{'
	JUMP @statement_label       ; Try next match

	;; Deal with { statements }
	CALLI R15 @recursive_statement
	JUMP @statement_done        ; All done

:statement_label
	CMPSKIPI.E R0 58            ; If GLOBAL_TOKEN->S[0] != ':'
	JUMP @statement_collect_local ; Try next match

	;; Deal with :label
	LOAD32 R0 R13 8             ; Using GLOBAL_TOKEN->S
	COPY R1 R12                 ; Using OUT
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put OUT in the correct place
	LOADUI R0 $statement_string0 ; Using label string
	CALLI R15 @emit             ; emit it
	MOVE R12 R0                 ; Update OUT
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	JUMP @statement_done

:statement_collect_local
	LOADUI R0 $struct           ; Using "struct"
	LOAD32 R1 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @match            ; IF GLOBAL_TOKEN->S == "struct"
	JUMP.NZ R0 @statement_collect_local_0

	;; Otherwise check if it is a primitive
	LOADUI R0 $prim_types       ; Using the Primitive types list
	SWAP R0 R1                  ; Put in correct order
	CALLI R15 @lookup_type      ; Check if a primitive type
	JUMP.Z R0 @statement_process_if ; If not try the next one

:statement_collect_local_0
	CALLI R15 @collect_local    ; Collect the local
	JUMP @statement_done        ; And move on

:statement_process_if
	JUMP @statement_process_do
	
	
	
	
:statement_process_do
	JUMP @statement_process_while
	
	
	
	
:statement_process_while
	JUMP @statement_process_for
	
	
	
	
:statement_process_for
	JUMP @statement_process_asm
	
	
	
	
:statement_process_asm
	JUMP @statement_goto
	
	
	
	
:statement_goto
	JUMP @statement_return_result
	
	
	
	
:statement_return_result
	JUMP @statement_break
	
	
	
	
:statement_break
	JUMP @statement_continue


:statement_continue
	JUMP @statement_expression

:statement_expression
	HALT
	CALLI R15 @line_error
	HALT

:statement_done
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	POPR R0 R15                 ; Restore R0
	RET R15

:statement_string0
	"	#C goto label
"


	
	
	
:expression
	RET R15
	
	
	
	
	
	


;; collect_local function
;; Recieves struct token_list* global_token in R13,
;;	struct token_list* out in R12,
;;	struct token_list* string_list in R11
;;	struct token_list* global_list in R10
;;	and struct token_list* FUNC in R9
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns the token_lists modified
:collect_local
	PUSHR R0 R15                ; Protect R0
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	CALLI R15 @type_name        ; Get it's type
	MOVE R1 R0                  ; Prepare for call
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	LOAD32 R2 R9 4              ; FUNC->LOCALS
	CALLI R15 @sym_declare      ; SET A
	MOVE R2 R0                  ; Protect A

	;; Figure out depth
	LOADUI R0 $main_string      ; Using "main"
	LOAD32 R1 R9 8              ; FUNC->S
	CALLI R15 @match            ; IF FUNC->S == "main"
	JUMP.Z R0 @collect_local_0  ; Try next
	LOAD32 R0 R9 4              ; FUNC->LOCALS
	JUMP.NZ R0 @collect_local_0 ; Try next

	LOADI R0 -4                 ; The default depth for main
	STORE32 R0 R2 16            ; A->DEPTH = -4
	JUMP @collect_local_output  ; Deal with header

:collect_local_0
	LOAD32 R0 R9 16             ; FUNC->ARGS
	JUMP.NZ R0 @collect_local_1 ; Try Next
	LOAD32 R0 R9 4              ; FUNC->LOCALS
	JUMP.NZ R0 @collect_local_1 ; Try Next

	LOADI R0 -8                 ; The default depth for foo()
	STORE32 R0 R2 16            ; A->DEPTH = -4
	JUMP @collect_local_output  ; Deal with header

:collect_local_1
	LOAD32 R0 R9 4              ; FUNC->LOCALS
	JUMP.NZ R0 @collect_local_2 ; Try Next

	LOAD32 R0 R9 16             ; FUNC->ARGS
	LOAD32 R0 R0 16             ; FUNC->ARGS->DEPTH
	SUBI R0 R0 8                ; DEPTH = FUNC->ARGS->DEPTH - 8
	STORE32 R0 R2 16            ; A->DEPTH = DEPTH
	JUMP @collect_local_output  ; Deal with header

:collect_local_2
	LOAD32 R0 R9 4              ; FUNC->LOCALS
	LOAD32 R0 R0 16             ; FUNC->LOCALS->DEPTH
	SUBI R0 R0 4                ; DEPTH = FUNC->LOCALS->DEPTH - 4
	STORE32 R0 R2 16            ; A->DEPTH = DEPTH

:collect_local_output
	STORE32 R2 R9 4             ; FUNC->LOCALS = A

	;; Output header
	LOADUI R0 $collect_local_string0 ; Starting with the comment
	COPY R1 R12                 ; Put OUT in the correct place
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put OUT in the correct place
	LOAD32 R0 R2 8              ; A->S
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put OUT in the correct place
	LOADUI R0 $newline          ; Using "\n"
	CALLI R15 @emit             ; emit it
	MOVE R12 R0                 ; Update OUT
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT

	;; Deal with possible assignment
	LOADUI R0 $equal            ; Using "="
	LOAD32 R1 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @match            ; IF GLOBAL_TOKEN->S == "="
	JUMP.Z R0 @collect_local_nonassign

	;; Deal with assignment of the local
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	CALLI R15 @expression       ; Update OUT with the evaluation of the Expression

:collect_local_nonassign
	LOADUI R0 $collect_local_string1 ; Our error message
	LOADUI R1 $semicolon        ; Using ";"
	CALLI R15 @require_match    ; Make sure GLOBAL_TOKEN->S == ";"

	;; Final Footer
	LOADUI R0 $collect_local_string2 ; Add our PUSH statement
	COPY R1 R12                 ; Using OUT
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put OUT in the proper place
	LOAD32 R0 R2 8              ; A->S
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put OUT in the proper place
	LOADUI R0 $newline          ; Using "\n"
	CALLI R15 @emit             ; emit it
	MOVE R12 R0                 ; Update OUT

	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	POPR R0 R15                 ; Restore R0
	RET R15

:collect_local_string0
	"# Defining local "
:collect_local_string1
	"ERROR in collect_local
Missing ;
"
:collect_local_string2
	"PUSH_eax	#"


;; collect_arguments function
;; Recieves struct token_list* global_token in R13,
;;	struct token_list* out in R12,
;;	struct token_list* string_list in R11
;;	struct token_list* global_list in R10
;;	and struct token_list* FUNC in R9
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns the token_lists modified
:collect_arguments
	PUSHR R0 R15                ; Protect R0
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
:collect_arguments_iter
	LOADUI R0 $close_paren      ; Using ")"
	LOAD32 R1 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @match            ; IF GLOBAL_TOKEN->S == ")"
	JUMP.NZ R0 @collect_arguments_done ; Be done

	;; Collect the arguments
	CALLI R15 @type_name        ; Get what type we are working with
	MOVE R1 R0                  ; Put TYPE where it will be used
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	LOADU8 R0 R0 0              ; GLOBAL_TOKEN->S[0]
	CMPSKIPI.NE R0 41           ; IF GLOBAL_TOKEN->S[0] == ')'
	JUMP @collect_arguments_iter3 ; foo(int,char,void) doesn't need anything done

	;; Check for foo(int a,...)
	CMPSKIPI.NE R0 41           ; IF GLOBAL_TOKEN->S[0] == ','
	JUMP @collect_arguments_iter3 ; Looks like final case

	;; Deal with foo(int a, ...)
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	LOAD32 R2 R9 16             ; FUNC->ARGUMENTS
	CALLI R15 @sym_declare      ; Get A
	MOVE R2 R0                  ; Get A out of the way

	;; Find special case for argument address
	LOAD32 R1 R9 8              ; FUNC->S
	LOADUI R0 $main_string      ; Using "main"
	CALLI R15 @match            ; IF FUNC->S == "main"
	JUMP.Z R0 @collect_arguments_func

	;; Deal with special case of main
	LOAD32 R1 R2 8              ; A->S
	LOADUI R0 $argc_string      ; "argc"
	CALLI R15 @match            ; IF A->S == "argc"
	JUMP.Z R0 @collect_arguments_argv ; If not try argv

	LOADUI R0 4                 ; Prepare for Store
	STORE32 R0 R2 16            ; argc => A->DEPTH = 4
	JUMP @collect_arguments_iter2

:collect_arguments_argv
	;; argv => A->DEPTH = 8
	LOADUI R0 $argv_string      ; "argv"
	CALLI R15 @match            ; IF A->S == "argv"
	JUMP.Z R0 @collect_arguments_iter2

	LOADUI R0 8                 ; Prepare for Store
	STORE32 R0 R2 16            ; argc => A->DEPTH = 8
	JUMP @collect_arguments_iter2

:collect_arguments_func
	LOAD32 R0 R9 16             ; FUNC->ARGS
	CMPSKIPI.NE R0 0            ; IF NULL == FUNC->ARGS
	LOAD32 R0 R0 16             ; FUNC->ARGS->DEPTH
	SUBI R0 R0 4                ; FUNC->ARGS->DEPTH - 4 or NULL - 4 (-4)
	STORE32 R0 R2 16            ; A->DEPTH = VALUE

:collect_arguments_iter2
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	STORE32 R2 R9 16            ; FUNC->ARGUMENTS = A

:collect_arguments_iter3
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	LOADU8 R0 R0 0              ; GLOBAL_TOKEN->S[0]
	CMPSKIPI.NE R0 44           ; IF GLOBAL_TOKEN->S[0] == ','
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	JUMP @collect_arguments_iter ; Keep looping

:collect_arguments_done
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	POPR R0 R15                 ; Restore R0
	RET R15


;; declare_function function
;; Recieves struct token_list* global_token in R13,
;;	struct token_list* out in R12,
;;	struct token_list* string_list in R11
;;	and struct token_list* global_list in R10
;; SETS R9 to struct token_list* FUNC
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns the token_lists modified
:declare_function
	PUSHR R0 R15                ; Protect R0
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	FALSE R0                    ; Using Zero
	STORER32 R0 @current_count  ; CURRENT_COUNT = 0
	LOAD32 R0 R13 4             ; GLOBAL_TOKEN->PREV
	LOAD32 R0 R0 8              ; GLOBAL_TOKEN->PREV->S
	FALSE R1                    ; Passing NULL
	LOADUI R2 $global_function_list ; where the global function list is located
	LOAD32 R2 R2 0              ; Loaded
	CALLI R15 @sym_declare      ; declare FUNC
	STORE32 R0 R2 0             ; GLOBAL_FUNCTION_LIST = FUNC
	MOVE R9 R0                  ; SETS FUNC
	CALLI R15 @collect_arguments ; Collect function arguments
	LOAD32 R2 R13 8             ; GLOBAL_TOKEN->S
	LOADU8 R0 R2 0              ; GLOBAL_TOKEN->S[0]
	CMPSKIPI.NE R0 59           ; IF GLOBAL_TOKEN->S[0] == ';'
	JUMP @declare_function_prototype ; Don't waste time

	;; Looks like it is an actual function definition
	LOADUI R0 $declare_function_string0 ; Using first string
	COPY R1 R12                 ; And OUT
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put OUT in the correct place
	LOAD32 R0 R9 8              ; Using FUNC->S
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put OUT in the correct place
	LOADUI R0 $newline          ; Using "\n"
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put OUT in the correct place
	LOADUI R0 $declare_function_string1 ; Using second string
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put OUT in the correct place
	LOAD32 R0 R9 8              ; Using FUNC->S
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put OUT in the correct place
	LOADUI R0 $newline          ; Using "\n"
	CALLI R15 @emit             ; emit it
	MOVE R12 R0                 ; Update OUT

	;; Check if main function
	MOVE R1 R2                  ; Using GLOBAL_TOKEN->S
	LOADUI R0 $main_string      ; Using "main"
	CALLI R15 @match            ; check if they match
	JUMP.Z R0 @declare_function_nonmain ; Skip work if they don't

	;; Deal with main function
	LOADUI R0 $declare_function_string2 ; Using first string
	COPY R1 R12                 ; And OUT
	CALLI R15 @emit             ; emit it
	MOVE R12 R0                 ; Update OUT

:declare_function_nonmain
	FALSE R1                    ; Cleaning up before call
	CALLI R15 @statement        ; Collect the statement

	;; Prevent Duplicate Returns
	LOAD32 R1 R12 8             ; OUT->S
	LOADUI R0 $declare_function_string3 ; Our final string
	CALLI R15 @match            ; Check for Match
	JUMP.NZ R0 @declare_function_done ; Clean up

	;; Deal with adding the return
	LOADUI R0 $declare_function_string3 ; Our final string
	COPY R1 R12                 ; Using OUT
	CALLI R15 @emit             ; emit it
	MOVE R12 R0                 ; Update OUT

:declare_function_done
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	POPR R0 R15                 ; Restore R0
	RET R15

:declare_function_prototype
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	JUMP @declare_function_done ; Clean up

:declare_function_string0
	"# Defining function "
:declare_function_string1
	":FUNCTION_"
:declare_function_string2
	"COPY_esp_to_ebp	# Deal with special case
"
:declare_function_string3
	"RETURN
"

:current_count
	NOP


;; program function
;; Recieves struct token_list* global_token in R13,
;;	struct token_list* out in R12,
;;	struct token_list* string_list in R11
;;	and struct token_list* global_list in R10
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns the token_lists modified
:program
	PUSHR R0 R15                ; Protect R0
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	PUSHR R3 R15                ; Protect R3
:program_iter
	JUMP.Z R13 @program_done    ; Looks like we read all the tokens
	LOADUI R0 $constant         ; Using the constant string
	LOAD32 R1 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @match            ; Check if they match
	JUMP.Z R0 @program_type     ; Looks like not

	;; Deal with CONSTANT case
	LOADUI R3 $global_constant_list ; Where we store our global constant
	LOAD32 R2 R3 0              ; Get contents of global constants
	FALSE R1                    ; Set NULL
	LOAD32 R0 R13 0             ; GLOBAL_TOKEN->NEXT
	LOAD32 R0 R0 8              ; GLOBAL_TOKEN->NEXT->S
	CALLI R15 @sym_declare      ; Declare the global constant
	STORE32 R0 R3 0             ; Update global constant
	LOAD32 R2 R13 0             ; GLOBAL_TOKEN->NEXT
	LOAD32 R2 R2 0              ; GLOBAL_TOKEN->NEXT->NEXT
	STORE32 R0 R2 16            ; GLOBAL_CONSTANT_LIST->ARGUMENTS = GLOBAL_TOKEN->NEXT->NEXT
	LOAD32 R13 R2 0             ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT->NEXT->NEXT
	JUMP @program_iter          ; Loop again

:program_type
	CALLI R15 @type_name        ; Get the type
	JUMP.Z R0 @program_iter     ; If newly defined type iterate

	;; Looks like we got a defined type
	MOVE R1 R0                  ; Put the type where it can be used
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	LOADUI R3 $global_symbol_list ; Get address of global symbol list
	LOAD32 R2 R3 0              ; GLOBAL_SYMBOLS_LIST
	CALLI R15 @sym_declare      ; Declare that global symbol
	STORE32 R0 R3 0             ; Update global symbol list

	LOAD32 R3 R13 8             ; GLOBAL_TOKEN->S
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	LOADUI R0 $semicolon        ; Get semicolon string
	LOAD32 R1 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @match            ; Check if they match
	JUMP.Z R0 @program_function ; If not a match

	;; Deal with case of TYPE NAME;
	COPY R1 R10                 ; Using GLOBALS_LIST
	LOADUI R0 $program_string0  ; Using the GLOBAL_ prefix
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Move new GLOBALS_LIST into Place
	MOVE R0 R3                  ; Use GLOBAL_TOKEN->PREV->S
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Move new GLOBALS_LIST into Place
	LOADUI R0 $program_string1  ; Using the NOP postfix
	CALLI R15 @emit             ; emit it
	MOVE R10 R0                 ; Move new GLOBALS_LIST into Place
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	JUMP @program_iter

:program_function
	LOADUI R0 $open_paren       ; Get open paren string
	CALLI R15 @match            ; Check if they match
	JUMP.Z R0 @program_assign   ; If not a match

	;; Deal with case of TYPE NAME(...)
	CALLI R15 @declare_function
	JUMP @program_iter

:program_assign
	LOADUI R0 $equal            ; Get equal string
	CALLI R15 @match            ; Check if they match
	JUMP.Z R0 @program_error    ; If not a match
	COPY R1 R10                 ; Using GLOBALS_LIST
	LOADUI R0 $program_string0  ; Using the GLOBAL_ prefix
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Move new GLOBALS_LIST into Place
	MOVE R0 R3                  ; Use GLOBAL_TOKEN->PREV->S
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Move new GLOBALS_LIST into Place
	LOADUI R0 $newline          ; Using the Newline postfix
	CALLI R15 @emit             ; emit it
	MOVE R10 R0                 ; Update GLOBALS_LIST
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	LOADU8 R0 R0 0              ; GLOBAL_TOKEN->S[0]
	LOADUI R1 $digit_chars      ; 0-9
	CALLI R15 @in_set           ; Figure out if in set
	JUMP.Z R0 @program_assign_string ; If not in sets

	;; Looks like we have an int
	COPY R1 R10                 ; Using GLOBALS_LIST
	LOADUI R0 $percent          ; Using percent prefix
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put GLOBALS_LIST into Place
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @emit             ; emit it
	MOVE R1 R0                  ; Put GLOBALS_LIST into Place
	LOADUI R0 $newline          ; Using newline postfix
	CALLI R15 @emit             ; emit it
	MOVE R10 R0                 ; Update GLOBALS_LIST
	JUMP @program_assign_done   ; Move on

:program_assign_string
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	LOADU8 R0 R0 0              ; GLOBAL_TOKEN->S[0]
	CMPSKIPI.E R0 34            ; If GLOBAL_TOKEN->S[0] == '"'
	JUMP @program_error         ; If not we hit an error

	;; Looks like we have a string
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @parse_string     ; Parse it into useful form
	COPY R1 R10                 ; GLOBALS_LIST
	CALLI R15 @emit             ; emit it
	MOVE R10 R0                 ; Update GLOBALS_LIST

:program_assign_done
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	LOADUI R0 $program_string4  ; Potential error message
	LOADUI R1 $semicolon        ; Checking for ;
	CALLI R15 @require_match    ; Catch those errors
	JUMP @program_iter

:program_error
	LOADUI R0 $program_string2  ; message part 1
	FALSE R1                    ; Show to user
	CALLI R15 @file_print       ; write
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @file_print       ; write
	LOADUI R0 $program_string3  ; message part 2
	CALLI R15 @file_print       ; write
	CALLI R15 @line_error       ; Provide a meaningful error message
	HALT

:program_done
	POPR R3 R15                 ; Restore R3
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	POPR R0 R15                 ; Restore R0
	RET R15

:program_string0
	":GLOBAL_"
:program_string1
	"
NOP
"
:program_string2
	"Recieved "
:program_string3
	" in program
"
:program_string4
"ERROR in Program
Missing ;
"


;; sym_declare function
;; Recieves char* in R0, struct type* in R1, struct token_list* in R2
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns struct token_list* in R0
:sym_declare
	PUSHR R3 R15                ; Protect R3
	COPY R3 R14                 ; Get A
	ADDUI R14 R14 20            ; CALLOC struct token_list
	STORE32 R2 R3 0             ; A->NEXT = LIST
	STORE32 R0 R3 8             ; A->S = S
	STORE32 R1 R3 12            ; A->TYPE = T
	MOVE R0 R3                  ; Prepare for Return
	POPR R3 R15                 ; Restore R3
	RET R15


;; emit function
;; Recieves char* in R0, struct token_list* in R1
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns struct token_list* in R0
:emit
	PUSHR R2 R15                ; Protect R2
	COPY R2 R14                 ; Pointer to T
	ADDUI R14 R14 20            ; CALLOC struct token_list
	STORE32 R1 R2 0             ; T->NEXT = HEAD
	STORE32 R0 R2 8             ; T->S = S
	MOVE R0 R2                  ; Put T in proper spot for return
	POPR R2 R15                 ; Restore R2
	RET R15


;; file_print function
;; Recieves pointer to string in R0 and FILE* in R1
;; Returns nothing
:file_print
	PUSHR R2 R15                ; Protect R2 from Overwrite
	MOVE R2 R0                  ; Put string pointer into place
:file_print_read
	LOAD8 R0 R2 0               ; Get a char
	JUMP.Z R0 @file_print_done  ; If NULL be done
	FPUTC                       ; Write the Char
	ADDUI R2 R2 1               ; Point at next CHAR
	JUMP @file_print_read       ; Loop again
:file_print_done
	POPR R2 R15                 ; Restore R2
	RET R15


;; recursive_output function
;; Recieves token_list in R0 and FILE* in R1
;; Returns nothing and alters nothing
:recursive_output
	JUMP.Z R0 @recursive_output_abort ; Abort if NULL
	PUSHR R2 R15                ; Preserve R2 from recursion
	MOVE R2 R0                  ; Preserve R0 from recursion
	LOAD32 R0 R2 0              ; Using I->NEXT
	CALLI R15 @recursive_output ; Recurse
	LOAD32 R0 R2 8              ; Using I->S
	CALLI R15 @file_print       ; Write the string
	MOVE R0 R2                  ; Put R0 back
	POPR R2 R15                 ; Restore R0
:recursive_output_abort
	RET R15


;; match function
;; Recieves a CHAR* in R0, CHAR* in R1
;; Returns Bool in R0 indicating if strings match
:match
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	PUSHR R3 R15                ; Protect R3
	PUSHR R4 R15                ; Protect R4
	MOVE R2 R0                  ; Put First string in place
	MOVE R3 R1                  ; Put Second string in place
	LOADUI R4 0                 ; Set initial index of 0
:match_cmpbyte
	LOADXU8 R0 R2 R4            ; Get a byte of our first string
	LOADXU8 R1 R3 R4            ; Get a byte of our second string
	ADDUI R4 R4 1               ; Prep for next loop
	CMPSKIP.E R1 R0             ; Compare the bytes
	FALSE R1                    ; Set FALSE
	JUMP.NZ R1 @match_cmpbyte   ; Loop if bytes are equal
;; Done
	CMPSKIPI.NE R0 0            ; If ended loop with everything matching
	TRUE R1                     ; Set as TRUE
	MOVE R0 R1                  ; Prepare for return
	POPR R4 R15                 ; Restore R4
	POPR R3 R15                 ; Restore R3
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	RET R15


;; lookup_type function
;; Recieves a CHAR* in R0 and struct type* in R1
;; Returns struct type* in R0 or NULL if no match
:lookup_type
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	MOVE R2 R1                  ; Put START in correct place
	MOVE R1 R0                  ; Put S in correct place
:lookup_type_iter
	LOAD32 R0 R2 24             ; Get I->NAME
	CALLI R15 @match            ; Check if I->NAME == S
	JUMP.NZ R0 @lookup_type_done ; If match found be done
	LOAD32 R2 R2 0              ; I = I->NEXT
	JUMP.NZ R2 @lookup_type_iter ; Otherwise iterate until I == NULL
:lookup_type_done
	MOVE R0 R2                  ; Our answer (I or NULL)
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	RET R15


;; build_member function
;; Recieves a struct type* in R0, int in R1 and int in R2
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Modifies R2 to current member_size
;; Returns struct type* in R0
:build_member
	PUSHR R3 R15                ; Protect R3
	PUSHR R4 R15                ; Protect R4
	PUSHR R5 R15                ; Protect R5
	MOVE R4 R0                  ; Protect LAST
	CALLI R15 @type_name        ; Get MEMBER_TYPE
	COPY R3 R14                 ; SET I
	ADDUI R14 R14 28            ; CALLOC struct type
	LOAD32 R5 R13 8             ; GLOBAL_TOKEN->S
	STORE32 R5 R3 24            ; I->NAME = GLOBAL_TOKEN->S
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	STORE32 R4 R3 16            ; I->MEMBERS = LAST
	LOAD32 R2 R0 4              ; MEMBER_SIZE = MEMBER_TYPE->SIZE
	STORE32 R2 R3 4             ; I->SIZE = MEMBER_SIZE
	STORE32 R0 R3 20            ; I->TYPE = MEMBER_TYPE
	STORE32 R1 R3 8             ; I->OFFSET = OFFSET
	MOVE R0 R3                  ; RETURN I in R0
	POPR R5 R15                 ; Restore R5
	POPR R4 R15                 ; Restore R4
	POPR R3 R15                 ; Restore R3
	RET R15


;; build_union function
;; Recieves a struct type* in R0, int in R1 and int in R2
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Modifies R2 to current member_size
;; Returns struct type* in R0
:build_union
	PUSHR R3 R15                ; Protect R3
	PUSHR R4 R15                ; Protect R4
	PUSHR R5 R15                ; Protect R5
	MOVE R4 R0                  ; Protect LAST
	MOVE R3 R1                  ; Protect OFFSET
	FALSE R5                    ; SIZE = 0
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	LOADUI R0 $build_union_string0 ; ERROR MESSAGE
	LOADUI R1 $open_curly_brace ; OPEN CURLY BRACE
	CALLI R15 @require_match    ; Ensure we have that curly brace
:build_union_iter
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	LOADU8 R0 R0 0              ; GLOBAL_TOKEN->S[0]
	LOADUI R1 125               ; numerical value of }
	CMPJUMPI.E R0 R1 @build_union_done ; No more looping required
	MOVE R0 R4                  ; We are passing last to be overwritten
	MOVE R1 R3                  ; We are also passing OFFSET
	CALLI R15 @build_member     ; To build_member to get new LAST and new member_size
	CMPSKIP.LE R2 R5            ; If MEMBER_SIZE > SIZE
	COPY R5 R2                  ; SIZE = MEMMER_SIZE
	MOVE R4 R0                  ; Protect LAST
	MOVE R3 R1                  ; Protect OFFSET
	LOADUI R0 $build_union_string1 ; ERROR MESSAGE
	LOADUI R1 $semicolon        ; SEMICOLON
	CALLI R15 @require_match    ; Ensure we have that curly brace
	JUMP @build_union_iter      ; Loop until we get that closing curly brace
:build_union_done
	MOVE R2 R5                  ; Setting MEMBER_SIZE = SIZE
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	MOVE R1 R3                  ; Restore OFFSET
	MOVE R0 R4                  ; Restore LAST as we are turning that
	POPR R5 R15                 ; Restore R5
	POPR R4 R15                 ; Restore R4
	POPR R3 R15                 ; Restore R3
	RET R15

:build_union_string0
"ERROR in build_union
Missing {
"
:build_union_string1
"ERROR in build_union
Missing ;
"


;; create_struct function
;; Recieves Nothing
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns Nothing
:create_struct
	PUSHR R0 R15                ; Protect R0
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	PUSHR R3 R15                ; Protect R3
	PUSHR R4 R15                ; Protect R4
	PUSHR R5 R15                ; Protect R5
	PUSHR R6 R15                ; Protect R6
	FALSE R5                    ; OFFSET = 0
	FALSE R2                    ; MEMBER_SIZE = 0
	COPY R3 R14                 ; SET HEAD
	ADDUI R14 R14 28            ; CALLOC struct type
	COPY R4 R14                 ; SET I
	ADDUI R14 R14 28            ; CALLOC struct type
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	STORE32 R0 R3 24            ; HEAD->NAME = GLOBAL_TOKEN->S
	STORE32 R0 R4 24            ; I->NAME = GLOBAL_TOKEN->S
	STORE32 R4 R3 12            ; HEAD->INDIRECT = I
	STORE32 R3 R4 12            ; I->INDIRECT - HEAD
	LOADUI R0 $global_types     ; Get Address of GLOBAL_TYPES
	LOAD32 R0 R0 0              ; Current pointer to GLOBAL_TYPES
	STORE R0 R3 0               ; HEAD->NEXT = GLOBAL_TYPES
	LOADUI R0 $global_types     ; Get Address of GLOBAL_TYPES
	STORE R3 R0 0               ; GLOBAL_TYPES = HEAD
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	LOADUI R0 4                 ; Standard Pointer SIZE
	STORE32 R0 R4 4             ; I->SIZE = 4
	LOADUI R0 $create_struct_string0 ; ERROR MESSAGE
	LOADUI R1 $open_curly_brace ; OPEN CURLY BRACE
	CALLI R15 @require_match    ; Ensure we have that curly brace
	FALSE R6                    ; LAST = NULL
:create_struct_iter
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	LOADU8 R0 R0 0              ; GLOBAL_TOKEN->S[0]
	LOADUI R1 125               ; Numerical value of }
	CMPJUMPI.E R0 R1 @create_struct_done ; Stop looping if match
	LOADUI R1 $union            ; Pointer to string UNION
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @match            ; Check if they Match
	SWAP R0 R6                  ; Put LAST in place
	MOVE R1 R5                  ; Put OFFSET in place
	JUMP.NZ R6 @create_struct_union ; Deal with union case

	;; Deal with standard member case
	CALLI R15 @build_member     ; Sets new LAST and MEMBER_SIZE
	JUMP @create_struct_iter2   ; reset for loop

:create_struct_union
	CALLI R15 @build_union

:create_struct_iter2
	ADD R5 R1 R2                ; OFFSET = OFFSET + MEMBER_SIZE
	SWAP R0 R6                  ; Put LAST in place
	LOADUI R0 $create_struct_string1 ; ERROR MESSAGE
	LOADUI R1 $semicolon        ; SEMICOLON
	CALLI R15 @require_match    ; Ensure we have that semicolon
	JUMP @create_struct_iter    ; Keep Looping

:create_struct_done
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	LOADUI R0 $create_struct_string1 ; ERROR MESSAGE
	LOADUI R1 $semicolon        ; SEMICOLON
	CALLI R15 @require_match    ; Ensure we have that semicolon
	STORE32 R5 R3 4             ; HEAD->SIZE = OFFSET
	STORE32 R6 R3 16            ; HEAD->MEMBERS = LAST
	STORE32 R6 R4 16            ; I->MEMBERS = LAST
	POPR R6 R15                 ; Restore R6
	POPR R5 R15                 ; Restore R5
	POPR R4 R15                 ; Restore R4
	POPR R3 R15                 ; Restore R3
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	POPR R0 R15                 ; Restore R0
	RET R15

:create_struct_string0
"ERROR in create_struct
Missing {
"
:create_struct_string1
"ERROR in create_struct
Missing ;
"


;; type_name function
;; Recieves Nothing
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns struct type* in R0
:type_name
	PUSHR R1 R15                ; Protect R1
	PUSHR R2 R15                ; Protect R2
	LOADUI R0 $struct           ; String for struct for comparison
	LOAD32 R1 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @match            ; Check if they match
	CMPSKIPI.E R0 0             ; If STRUCTURE
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	LOAD32 R2 R13 8             ; GLOBAL_TOKEN->S
	LOADUI R1 $global_types     ; Check using the GLOBAL TYPES LIST
	LOAD32 R1 R1 0              ; Need to load address of first node
	SWAP R0 R2                  ; Put GLOBAL_TOKEN->S in the right place
	CALLI R15 @lookup_type      ; RET = lookup_type(GLOBAL_TOKEN->S)
	MOVE R1 R2                  ; Put STRUCTURE in the right place
	CMPSKIP.E R0 R1             ; If RET == NULL and !STRUCTURE
	JUMP @type_name_struct      ; Guess not

	;; Exit with useful error message
	FALSE R1                    ; We will want to be writing the error message for the Human
	LOADUI R0 $type_name_string0 ; The first string
	CALLI R15 @file_print       ; Display it
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @file_print       ; Display it
	LOADUI R0 $newline          ; Terminating linefeed
	CALLI R15 @file_print       ; Display it
	CALLI R15 @line_error       ; Give useful debug info
	HALT                        ; Just exit

:type_name_struct
	JUMP.NZ R0 @type_name_iter  ; If was found
	CALLI R15 @create_struct    ; Otherwise create it
	JUMP @type_name_done        ; and be done

:type_name_iter
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	LOAD32 R1 R13 8             ; GLOBAL_TOKEN->S
	LOADU8 R1 R1 0              ; GLOBAL_TOKEN->S[0]
	CMPSKIPI.E R1 42            ; if GLOBAL_TOKEN->S[0] == '*'
	JUMP @type_name_done        ; Looks like Nope
	LOAD32 R0 R0 12             ; RET = RET->INDIRECT
	JUMP @type_name_iter        ; Keep looping

:type_name_done
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	RET R15

:type_name_string0
"Unknown type "


;; line_error function
;; Recieves Nothing
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns nothing
:line_error
	PUSHR R0 R15                ; Protect R0
	PUSHR R1 R15                ; Protect R1
	LOADUI R0 $line_error_string0 ; Our leading string
	FALSE R1                    ; We want the user to see
	CALLI R15 @file_print       ; Print it
	LOAD32 R0 R13 16            ; GLOBAL_TOKEN->LINENUMBER
	CALLI R15 @numerate_number  ; Get a string pointer for number
	CALLI R15 @file_print       ; And print it
	POPR R1 R15                 ; Restore R1
	POPR R0 R15                 ; Restore R0
	RET R15

:line_error_string0
	"In file: TTY1 On line: "


;; require_match function
;; Recieves char* in R0 and char* in R1
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns Nothing
:require_match
	PUSHR R0 R15                ; Protect R0
	PUSHR R2 R15                ; Protect R2
	MOVE R2 R0                  ; Get MESSAGE out of the way
	LOAD32 R0 R13 8             ; GLOBAL_TOKEN->S
	CALLI R15 @match            ; Check if GLOBAL_TOKEN->S == REQUIRED
	JUMP.NZ R0 @require_match_done ; Looks like it was a match

	;; Terminate with an error
	MOVE R0 R2                  ; Put MESSAGE in required spot
	FALSE R1                    ; We want to write for user
	CALLI R15 @file_print       ; Write it
	CALLI R15 @line_error       ; And provide some debug info
	HALT                        ; Then Stop immediately

:require_match_done
	LOAD32 R13 R13 0            ; GLOBAL_TOKEN = GLOBAL_TOKEN->NEXT
	POPR R2 R15                 ; Restore R2
	POPR R0 R15                 ; Restore R0
	RET R15


;; numerate_number function
;; Recieves int in R0
;; R13 Holds pointer to global_token, R14 is HEAP Pointer
;; Returns pointer to string generated
:numerate_number
	PUSHR R1 R15                ; Preserve R1
	PUSHR R2 R15                ; Preserve R2
	PUSHR R3 R15                ; Preserve R3
	PUSHR R4 R15                ; Preserve R4
	PUSHR R5 R15                ; Preserve R5
	PUSHR R6 R15                ; Preserve R6
	MOVE R3 R0                  ; Move Integer out of the way
	COPY R1 R14                 ; Get pointer result
	ADDUI R14 R14 16            ; CALLOC the 16 chars of space
	FALSE R6                    ; Set index to 0

	JUMP.Z R3 @numerate_number_ZERO ; Deal with Special case of ZERO
	JUMP.P R3 @numerate_number_Positive
	LOADUI R0 45                ; Using -
	STOREX8 R0 R1 R6            ; write leading -
	ADDUI R6 R6 1               ; Increment by 1
	NOT R3 R3                   ; Flip into positive
	ADDUI R3 R3 1               ; Adjust twos

:numerate_number_Positive
	LOADR R2 @Max_Decimal       ; Starting from the Top
	LOADUI R5 10                ; We move down by 10
	FALSE R4                    ; Flag leading Zeros

:numerate_number_0
	DIVIDE R0 R3 R3 R2          ; Break off top 10
	CMPSKIPI.E R0 0             ; If Not Zero
	TRUE R4                     ; Flip the Flag

	JUMP.Z R4 @numerate_number_1 ; Skip leading Zeros
	ADDUI R0 R0 48              ; Shift into ASCII
	STOREX8 R0 R1 R6            ; write digit
	ADDUI R6 R6 1               ; Increment by 1

:numerate_number_1
	DIV R2 R2 R5                ; Look at next 10
	CMPSKIPI.E R2 0             ; If we reached the bottom STOP
	JUMP @numerate_number_0     ; Otherwise keep looping

:numerate_number_done
	LOADUI R0 10                ; Using LINEFEED
	STOREX8 R0 R1 R6            ; write
	ADDUI R6 R6 1               ; Increment by 1
	FALSE R0                    ; NULL Terminate
	STOREX8 R0 R1 R6            ; write
	MOVE R0 R1                  ; Return pointer to our string
	;; Cleanup
	POPR R6 R15                 ; Restore R6
	POPR R5 R15                 ; Restore R5
	POPR R4 R15                 ; Restore R4
	POPR R3 R15                 ; Restore R3
	POPR R2 R15                 ; Restore R2
	POPR R1 R15                 ; Restore R1
	RET R15

:numerate_number_ZERO
	LOADUI R0 48                ; Using Zero
	STOREX8 R0 R1 R6            ; write
	ADDUI R6 R6 1               ; Increment by 1
	JUMP @numerate_number_done  ; Be done

:Max_Decimal
	'3B9ACA00'


;; Keywords
:union
	"union"
:struct
	"struct"
:constant
	"CONSTANT"
:main_string
	"main"
:argc_string
	"argc"
:argv_string
	"argv"

;; Frequently Used strings
;; Generally used by require_match
:open_curly_brace
	"{"
:close_curly_brace
	"}"
:open_paren
	"("
:close_paren
	")"
:semicolon
	";"
:equal
	"="
:percent
	"%"
:newline
	"
"


;; Global types
;; NEXT (0), SIZE (4), OFFSET (8), INDIRECT (12), MEMBERS (16), TYPE (20), NAME (24)
:global_types
	&type_void

:prim_types
:type_void
	&type_int                   ; NEXT
	'00 00 00 04'               ; SIZE
	NOP                         ; OFFSET
	&type_void                  ; INDIRECT
	NOP                         ; MEMBERS
	&type_void                  ; TYPE
	&type_void_name             ; NAME
:type_void_name
	"void"

:type_int
	&type_char                  ; NEXT
	'00 00 00 04'               ; SIZE
	NOP                         ; OFFSET
	&type_int                   ; INDIRECT
	NOP                         ; MEMBERS
	&type_int                   ; TYPE
	&type_int_name              ; NAME
:type_int_name
	"int"

:type_char
	&type_file                  ; NEXT
	'00 00 00 01'               ; SIZE
	NOP                         ; OFFSET
	&type_char_indirect         ; INDIRECT
	NOP                         ; MEMBERS
	&type_char                  ; TYPE
	&type_char_name             ; NAME
:type_char_name
	"char"

:type_char_indirect
	&type_file                  ; NEXT
	'00 00 00 04'               ; SIZE
	NOP                         ; OFFSET
	&type_char_double_indirect  ; INDIRECT
	NOP                         ; MEMBERS
	&type_char_indirect         ; TYPE
	&type_char_indirect_name    ; NAME
:type_char_indirect_name
	"char*"

:type_char_double_indirect
	&type_file                  ; NEXT
	'00 00 00 04'               ; SIZE
	NOP                         ; OFFSET
	&type_char_double_indirect  ; INDIRECT
	NOP                         ; MEMBERS
	&type_char_indirect         ; TYPE
	&type_char_double_indirect_name ; NAME
:type_char_double_indirect_name
	"char**"

:type_file
	&type_function              ; NEXT
	'00 00 00 04'               ; SIZE
	NOP                         ; OFFSET
	&type_file                  ; INDIRECT
	NOP                         ; MEMBERS
	&type_file                  ; TYPE
	&type_file_name             ; NAME
:type_file_name
	"FILE"

:type_function
	&type_unsigned              ; NEXT
	'00 00 00 04'               ; SIZE
	NOP                         ; OFFSET
	&type_function              ; INDIRECT
	NOP                         ; MEMBERS
	&type_function              ; TYPE
	&type_function_name         ; NAME
:type_function_name
	"FUNCTION"

:type_unsigned
	NOP                         ; NEXT (NULL)
	'00 00 00 04'               ; SIZE
	NOP                         ; OFFSET
	&type_unsigned              ; INDIRECT
	NOP                         ; MEMBERS
	&type_unsigned              ; TYPE
	&type_unsigned_name         ; NAME
:type_unsigned_name
	"unsigned"


;; debug_list function
;; Recieves struct token_list* in R0
;; Prints contents of list and HALTS
;; Does not return
:debug_list
	MOVE R9 R0                  ; Protect the list Pointer
	FALSE R1                    ; Write to TTY

:debug_list_iter
	;; Header
	LOADUI R0 $debug_list_string0 ; Using our first string
	CALLI R15 @file_print       ; Print it
	COPY R0 R9                  ; Use address of pointer
	CALLI R15 @numerate_number  ; Convert it into a string
	CALLI R15 @file_print       ; Print it

	;; NEXT
	LOADUI R0 $debug_list_string1 ; Using our second string
	CALLI R15 @file_print       ; Print it
	LOAD32 R0 R9 0              ; Use address of pointer
	CALLI R15 @numerate_number  ; Convert it into a string
	CALLI R15 @file_print       ; Print it

	;; PREV
	LOADUI R0 $debug_list_string2 ; Using our third string
	CALLI R15 @file_print       ; Print it
	LOAD32 R0 R9 4              ; Use address of pointer
	CALLI R15 @numerate_number  ; Convert it into a string
	CALLI R15 @file_print       ; Print it

	;; S
	LOADUI R0 $debug_list_string3 ; Using our fourth string
	CALLI R15 @file_print       ; Print it
	LOAD32 R0 R9 8              ; Use address of pointer
	CALLI R15 @numerate_number  ; Convert it into a string
	CALLI R15 @file_print       ; Print it

	;; S Contents
	LOADUI R0 $debug_list_string4 ; Using our Prefix string
	CALLI R15 @file_print       ; Print it
	LOAD32 R0 R9 8              ; Use address of pointer
	CMPSKIPI.NE R0 0            ; If NULL Pointer
	LOADUI R0 $debug_list_string_null ; Give meaningful message instead
	CALLI R15 @file_print       ; Print it

	;; TYPE
	LOADUI R0 $debug_list_string5 ; Using our fifth string
	CALLI R15 @file_print       ; Print it
	LOAD32 R0 R9 12             ; Use address of pointer
	CALLI R15 @numerate_number  ; Convert it into a string
	CALLI R15 @file_print       ; Print it

	;; PREV
	LOADUI R0 $debug_list_string6 ; Using our sixth string
	CALLI R15 @file_print       ; Print it
	LOAD32 R0 R9 16             ; Use address of pointer
	CALLI R15 @numerate_number  ; Convert it into a string
	CALLI R15 @file_print       ; Print it

	;; Add some space
	LOADUI R0 10                ; Using NEWLINE
	FPUTC
	FPUTC

	;; Iterate if next not NULL
	LOAD32 R9 R9 0              ; TOKEN = TOKEN->NEXT
	JUMP.NZ R9 @debug_list_iter

	;; Looks lke we are done, wrap it up
	HALT


:debug_list_string0
"Token_list node at address: "
:debug_list_string1
	"NEXT address: "
:debug_list_string2
	"PREV address: "

:debug_list_string3
	"S address: "

:debug_list_string4
	"The contents of S are: "

:debug_list_string5
	"
TYPE address: "

:debug_list_string6
	"ARGUMENTS address: "

:debug_list_string_null
	">::<NULL>::<"

:STACK