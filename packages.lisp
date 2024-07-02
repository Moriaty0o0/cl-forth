;;; -*- Syntax: Common-Lisp; Base: 10 -*-
;;;
;;; Copyright (c) 2024 Gary Palter
;;;
;;; Licensed under the MIT License;
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;   https://github.com/gmpalter/cl-forth/tree/main?tab=MIT-1-ov-file#readme

(in-package #:cl-user)

(defpackage #:forth
  (:use #:common-lisp)
  #+CCL (:import-from #:ccl
                      #:fixnump
                      #:whitespacep
                      #:class-direct-slots
                      #:slot-definition-name
                      #:process-run-function
                      #:add-auto-flush-stream
                      #:remove-auto-flush-stream)
  #+SBCL (:import-from #:sb-int
                       #:fixnump
                       #:named-lambda)
  #+SBCL (:import-from #:sb-mop
                       #:class-direct-slots
                       #:slot-definition-name)
  #+LispWorks (:import-from #:lispworks
                            #:fixnump)
  #+LispWorks (:import-from #:harlequin-common-lisp
                            #:class-direct-slots
                            #:slot-definition-name)
  (:export #:forth-system
           #:forth-toplevel
           #:save-forth-system-to-template
           #:load-forth-system-from-template
           #:*exception-hook*
           #:*exception-prefix*
           #:*exit-hook*
           #:run-forth-process
           #:run))

(defpackage #:forth-words
  (:use))

(defpackage #:forth-ffi-symbols
  (:use))
