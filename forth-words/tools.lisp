;;; -*- Syntax: Common-Lisp; Base: 10 -*-
;;;
;;; Copyright (c) 2024 Gary Palter
;;;
;;; Licensed under the MIT License;
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;   https://opensource.org/license/mit

(in-package #:forth)

;;; Programming-Tools words as defined in Section 15 of the Forth 2012 specification

(define-word dump-stack (:word ".S")
  "( -- )"
  "Copy and display the values currently on the data stack. The format of the display is implementation-dependent"
  (show-stack data-stack base))

(define-word print-tos (:word "?")
  "( a-addr -- )"
  "Display the value stored at A-ADDR"
  (write-integer (cell-signed (memory-cell memory (stack-pop data-stack))) base))

(define-word dump-memory (:word "DUMP" :inlineable? nil)
  "( a-addr u -- )"
  "Display the contents of U consecutive addresses starting at ADDR. The format of the display is implementation dependent"
  (let* ((count (stack-pop data-stack))
         (address (stack-pop data-stack))
         (end-address (+ address count)))
    (loop while (plusp count)
          do (format t "~&$~16,'0X: " address)
             (loop with byte-address = address
                   ;; Four "cells" at a time
                   for i from 0 below 4
                   while (< byte-address end-address)
                   do (loop with pseudo-cell = 0
                            with top = (min (1- count) 7)
                            for j downfrom top to 0
                            do ;; Memory is little-endian
                               (setf pseudo-cell (logior (ash pseudo-cell 8) (memory-byte memory (+ byte-address j))))
                               (decf count)
                            finally (format t "~V,'0X " (* 2 (- top j)) pseudo-cell))
                   (incf byte-address +cell-size+))
             (incf address (* 4 +cell-size+)))
    (fresh-line)))

(define-word see (:word "SEE")
  "SEE <name>"
  "Display a human-readable representation of the named word’s definition."
  "CL-Forth displays either the Lisp code generated by CL-Forth or the resulting object code generated by the Lisp compiler"
  (let ((name (word files #\Space)))
    (when (null name)
      (forth-exception :zero-length-name))
    (let ((word (lookup word-lists name)))
      (if word
          (show-definition fs word)
          (forth-exception :undefined-word "~A is not defined" name)))))

(define-word show-words (:word "WORDS" :inlineable? nil)
  "List the definition names in the first word list of the search order. The format of the display is implementation-dependent"
  (show-words (first (word-lists-search-order word-lists))))


;;; Programming-Tools extension words as defined in Section 15 of the Forth 2012 specification

(define-forth-function assemble-native-code (fs)
  (let ((forms (with-output-to-string (forms)
                 (loop do
                   (multiple-value-bind (buffer >in)
                       (current-input-state files)
                     (let ((token (word files #\Space)))
                       (when (and token (string-equal token ";ENDCODE"))
                         (loop-finish)))
                     (write-line (subseq buffer >in) forms)
                     (unless (refill files)
                       (forth-exception :missing-endcode)))))))
    (with-input-from-string (forms forms)
      (with-standard-io-syntax
        (let ((*package* *forth-package*)
              (*read-eval* nil)
              (eof '#:eof))
          (loop for form = (read forms nil eof)
                until (eq form eof)
                do (push form (word-inline-forms (definition-word definition)))))))
    (finish-compilation fs)))

(define-word native-code-does> (:word ";CODE" :immediate? t :compile-only? t)
  "Compilation:  (C: colon-sys -- )"
  "Append the run-time semantics below to the current definition. End the current definition, allow it to be found in the"
  "dictionary, and enter interpretation state, consuming COLON-SYS. Subsequent characters in the parse area typically represent"
  "source code in a programming language, usually some form of assembly language. Those characters are processed in an"
  "implementation-defined manner, generating the corresponding machine code. The process continues, refilling the input buffer"
  "as needed, until an implementation-defined ending sequence is processed."
  "Run-time: ( -- ) (R: nest-sys -- )"
  "Replace the execution semantics of the most recent definition with the NAME execution semantics given below. Return control"
  "to the calling definition specified by NEST-SYS"
  "NAME Execution: ( i*x -- j*x )"
  "Execute the machine code sequence that was generated following ;CODE."
  (compile-does> fs)
  (assemble-native-code fs))

(define-word ahead (:word "AHEAD" :immediate? t :compile-only? t)
  "(C: — orig )"
  "At compile time, begin an unconditional forward branch by placing ORIG (the location of the unresolved branch)"
  "on the control-flow stack. The behavior is incomplete until the ORIG is resolved, e.g., by THEN."
  "At run time, resume execution at the location provided by the resolution of this ORIG"
  (let ((branch (make-branch-reference :ahead)))
    (stack-push control-flow-stack branch)
    (execute-branch fs branch)))

(define-word assembler (:word "ASSEMBLER")
  "Replace the first word list in the search order with the ASSEMBLER word list"
  (replace-top-of-search-order word-lists (word-list word-lists "ASSEMBLER" :if-not-found :create)))

(define-word bye (:word "BYE")
  "Return control to the host operating system, if any"
  (throw 'bye nil))

(define-word native-code (:word "CODE")
  "CODE <name>"
  "Skip leading space delimiters. Parse NAME delimited by a space. Create a definition for NAME, called a \"code definition\","
  "with the execution semantics defined below. Subsequent characters in the parse area typically represent source code in a"
  "programming language, usually some form of assembly language. Those characters are processed in an implementation-defined"
  "manner, generating the corresponding machine code. The process continues, refilling the input buffer as needed, until an"
  "implementation-defined ending sequence is processed."
  "NAME Execution: ( i*x -- j*x )"
  "Execute the machine code sequence that was generated following CODE."
  (let ((name (word files #\Space)))
    (when (null name)
      (forth-exception :zero-length-name))
    (begin-compilation fs name)
    (assemble-native-code fs)))

(define-word cs-pick (:word "CS-PICK")
  "(S: u -- ) (C: xu ... x0 -- xu ... x0 xu ) "
  "Place a copy of the uth control-stack entry on the top of the control stack. The zeroth item is on top of the"
  "control stack; i.e., 0 CS-PICK is equivalent to DUP and 1 CS-PICK is equivalent to OVER."
  (stack-pick control-flow-stack (cell-unsigned (stack-pop data-stack))))

(define-word cs-roll (:word "CS-ROLL")
  "(S: u -- ) (C: x(u-1) xu x(u+1) ... x0 -- x(u-1) x(u+1) ... x0 xu )"
  "Move the Uth control-stack entry to the top of the stack, pushing down all the control-stack entries in between."
  "The zeroth item is on top of the stack; i.e., 0 CS-ROLL does nothing, 1 CS-ROLL is equivalent to SWAP, and"
  "2 CS-ROLL is equivalent to ROT"
  (stack-roll control-flow-stack (cell-unsigned (stack-pop data-stack))))

(define-word editor (:word "EDITOR")
  "Replace the first word list in the search order with the EDITOR word list"
  (replace-top-of-search-order word-lists (word-list word-lists "EDITOR" :if-not-found :create)))

(define-word forget (:word "FORGET")
  "FORGET <name>"
  "Skip leading space delimiters. Parse NAME delimited by a space. Find NAME, then delete NAME from the dictionary along"
  "with all words added to the dictionary after NAME."
  "If the Search-Order word set is present, FORGET searches the compilation word list"
  (let ((name (word files #\Space)))
    (when (null name)
      (forth-exception :zero-length-name))
    (let ((word (search-dictionary (word-lists-compilation-word-list word-lists) name)))
      (when (null word)
        (forth-exception :undefined-word "~A is not defined" name))
      (forget word execution-tokens))))

;;; NOTE: This word pushes a vector of values onto the return stack rather than individual items.
;;;  A Forth program will crash if it doesn't maintain proper return stack discipline. But, that's true
;;;  anyway as the return "address" pushed/popped by a call is actually a structure (PSUEDO-PC).
(define-word save-values (:word "N>R")
  "( i*n +n -- ) (R: -- j*x +n )"
  "Remove N+1 items from the data stack and store them for later retrieval by NR>."
  "The return stack may be used to store the data"
  (let ((n (stack-pop data-stack)))
    ;; We have to flush the optimizer stack here as the optimizer can't track the data stack contents as
    ;; we're using a loop to pop the values off the data stack to be saved in the vector on the return stack.
    ;; The alternative of making this word and NR> not inlineable will not work as the vector would be pushed
    ;; above the return PC and would then be popped off when N>R returns, resulting in an "out of sync" exception
    (flush-optimizer-stack)
    (when (minusp n)
      (forth-exception :invalid-numeric-argument "N>R count can't be negative"))
    (let ((vector (make-array n :initial-element 0)))
      (dotimes (i n)
        (setf (aref vector (- n i 1)) (stack-pop data-stack)))
      (stack-push return-stack vector))))

(define-word nt-to-compile-xt (:word "NAME>COMPILE")
  "( nt -- x xt )"
  "X XT represents the compilation semantics of the word NT. The returned XT has the stack effect ( i*x x -- j*x )."
  "Executing XT consumes X and performs the compilation semantics of the word represented by NT"
  (let ((word (lookup-nt word-lists (stack-pop data-stack))))
    (multiple-value-bind (data xt)
        (create-compile-execution-token fs word)
      (stack-push data-stack data)
      (stack-push data-stack xt))))

(define-word nt-to-interpret-xt (:word "NAME>INTERPRET")
  "( nt -- xt | 0 )"
  "XT represents the interpretation semantics of the word NT. If NT has no interpretation semantics, NAME>INTERPRET returns 0"
  (let ((word (lookup-nt word-lists (stack-pop data-stack))))
    (if (word-compile-only? word)
        (stack-push data-stack 0)
        (stack-push data-stack (xt-token (word-execution-token word))))))

(define-word nt-to-string (:word "NAME>STRING")
  "( nt -- c-addr u )"
  "NAME>STRING returns the name of the word NT in the character string C-ADDR U"
  (let* ((word (lookup-nt word-lists (stack-pop data-stack)))
         (name>string-space (memory-name>string-space memory))
         (address (transient-space-base-address memory name>string-space)))
    (ensure-transient-space-holds memory name>string-space (length (word-name word)))
    (multiple-value-bind (forth-memory offset)
        (memory-decode-address memory address (length (word-name word)))
      (native-into-forth-string (word-name word) forth-memory offset))
    (stack-push data-stack address)
    (stack-push data-stack (length (word-name word)))
    (seal-transient-space memory name>string-space)))

(define-word retrieve-values (:word "NR>")
  "( -- i*x +n) (R: j*x +n -- )"
  "Retrieve the items previously stored by an invocation of N>R. N is the number of items placed on the data stack."
  ;; We have to flush the optimizer stack here as the optimizer can't track the data stack contents as
  ;; we're using a loop to push the saved values back onto the data stack.
  (flush-optimizer-stack)
  (let ((vector (stack-pop return-stack)))
    (unless (vectorp vector)
      (forth-exception :type-mismatch "Return stack out of sync"))
    (let ((n (length vector)))
      (dotimes (i n)
        (stack-push data-stack (aref vector i)))
      (stack-push data-stack n))))

(define-state-word %state :word "STATE")

(define-word synonym (:word "SYNONYM")
  "SYNONYM <newname> <oldname>"
  "Parse NEWNAME and OLDNAME delimited by a space. Create a definition for NEWNAME with the semantics of OLDNAME."
  "NEWNAME may be the same as OLDNAME; when looking up OLDNAME, NEWNAME shall not be found."
  (let ((new-name (word files #\Space))
        (old-name (word files #\Space)))
    (when (null new-name)
      (forth-exception :zero-length-name))
    (when (null old-name)
      (forth-exception :zero-length-name))
    (let ((old-word (lookup word-lists old-name)))
      (when (null old-word)
        (forth-exception :undefined-word "~A is not defined" old-name))
      (let ((new-word (make-word new-name (word-code old-word)
                                 :immediate? (word-immediate? old-word)
                                 :compile-only? (word-compile-only? old-word)
                                 :created-word? (word-created-word? old-word)
                                 :parameters (copy-parameters (word-parameters old-word)))))
        (setf (word-inlineable? new-word) (word-inlineable? old-word)
              (word-inline-forms new-word) (word-inline-forms old-word)
              (word-documentation new-word) (word-documentation old-word)
              (word-does> new-word) (word-does> old-word))
        (add-and-register-word fs new-word)))))

(define-word traverse-wordlist (:word "TRAVERSE-WORDLIST")
  "( i*x xt wid -- j*x )"
  "Remove WID and XT from the stack. Execute XT once for every word in the wordlist WID, passing the name token NT of the word"
  "to XT, until the wordlist is exhausted or until XT returns false."
  "The invoked XT has the stack effect ( k*x nt -- l*x flag )."
  "If FLAG is true, TRAVERSE-WORDLIST will continue with the next name, otherwise it will return. TRAVERSE-WORDLIST does not"
  "put any items other than NT on the stack when calling XT, so that XT can access and modify the rest of the stack."
  "TRAVERSE-WORDLIST may visit words in any order, with one exception: words with the same name are called in the order"
  "newest-to-oldest (possibly with other words in between)"
  (let* ((wid (stack-pop data-stack))
         (xt (stack-pop data-stack))
         (wl (lookup-wid word-lists wid)))
    (verify-execution-token execution-tokens xt)
    (flet ((do-nt (nt)
             (stack-push data-stack nt)
             (execute execution-tokens xt fs)
             (truep (stack-pop data-stack))))
      (traverse-wordlist wl #'do-nt))))

(define-word defined (:word "[DEFINED]" :immediate? t)
  "[DEFINED] <name>" "( -- flag )"
  "Skip leading space delimiters. Parse NAME delimited by a space. Return a true flag if name is the name of a word"
  "that can be found (according to the rules in the system’s FIND); otherwise return a false flag"
  (let ((name (word files #\Space)))
    (when (null name)
      (forth-exception :zero-length-name))
    (let ((word (lookup word-lists name)))
      (if word
          (stack-push data-stack +true+)
          (stack-push data-stack +false+)))))

(define-word interpreted-else (:word "[ELSE]" :immediate? t)
  "Skipping leading spaces, parse and discard space-delimited words from the parse area, including nested occurrences"
  "of [IF] ... [THEN] and [IF] ... [ELSE] ... [THEN], until the word [THEN] has been parsed and discarded."
  "If the parse area be- comes exhausted, it is refilled as with REFILL"
  (block interpreted-else
    (do ((nesting 0)
         (word (word files #\Space) (word files #\Space)))
        (nil)
      (cond ((null word)
             (unless (refill files)
               (forth-exception :if/then/else-exception)))
            ((string-equal word "[IF]")
             (incf nesting))
            ((string-equal word "[ELSE]")
             (when (zerop nesting)
               (return-from interpreted-else (values))))
            ((string-equal word "[THEN]")
             (if (zerop nesting)
                 (return-from interpreted-else (values))
                 (decf nesting)))))))

(define-word interpreted-if (:word "[IF]" :immediate? t)
  "( flag -- )"
  "If FLAG is true, do nothing. Otherwise, skipping leading spaces, parse and discard space-delimited words"
  "from the parse area, including nested occurrences of [IF]... [THEN] and [IF] ... [ELSE] ... [THEN], until either the"
  "word [ELSE] or the word [THEN] has been parsed and discarded. If the parse area becomes exhausted, it is refilled"
  "as with REFILL"
  (block interpreted-if
    (when (falsep (stack-pop data-stack))
      (do ((nesting 0)
           (word (word files #\Space) (word files #\Space)))
          (nil)
        (cond ((null word)
               (unless (refill files)
                 (forth-exception :if/then/else-exception)))
              ((string-equal word "[IF]")
               (incf nesting))
              ((string-equal word "[ELSE]")
               (when (zerop nesting)
                 (return-from interpreted-if (values))))
              ((string-equal word "[THEN]")
               (if (zerop nesting)
                   (return-from interpreted-if (values))
                   (decf nesting))))))))

(define-word interpreted-then (:word "[THEN]" :immediate? t)
  "Does nothing"
  nil)

(define-word undefined (:word "[UNDEFINED]" :immediate? t)
  "[UNDEFINED] <name>" "( -- flag )"
  "Skip leading space delimiters. Parse NAME delimited by a space. Return a false flag if NAME is the name of a word"
  "that can be found (according to the rules in the system’s FIND); otherwise return a true flag"
  (let ((name (word files #\Space)))
    (when (null name)
      (forth-exception :zero-length-name))
    (let ((word (lookup word-lists name)))
      (if word
          (stack-push data-stack +false+)
          (stack-push data-stack +true+)))))
