(in-package #:forth)

(defparameter *forth-words-package* (find-package '#:forth-words))


;;; Dictionaries

(defclass dictionary ()
  ((name :accessor dictionary-name :initarg :name)
   (wid :accessor dictionary-wid :initarg :wid)
   (last-ordinal :initform -1)
   (words :accessor dictionary-words :initform (make-hash-table :test #'equalp))
   (parent :accessor dictionary-parent :initform nil :initarg :parent))
  )

(defmethod print-object ((dict dictionary) stream)
  (print-unreadable-object (dict stream :type t :identity t)
    (write-string (dictionary-name dict) stream)))

(defmethod add-word ((dict dictionary) word &key override silent)
  (with-slots (last-ordinal words parent) dict
    (let ((old (gethash (word-name word) words)))
      (when old
        (unless silent
          (format t "~A isn't unique. " (word-name word)))
        (unless override
          (setf (word-previous word) old)))
      (setf (word-ordinal word) (incf last-ordinal))
      (note-new-word parent dict word)
      (setf (gethash (word-name word) words) word))))

(defmethod delete-word ((dict dictionary) xts word)
  (with-slots (words) dict
    (let ((name (word-name word))
          (old (word-previous word)))
      (delete-execution-token xts word)
      (cond (old
             (if (eq (word-parent old) dict)
                 (setf (gethash name words) old)
                 (remhash name words))
             (reregister-execution-token xts (word-execution-token word)))
            (t
             (remhash name words))))))

(defmethod show-words ((dict dictionary))
  (let* ((words (dictionary-words dict))
         (names nil))
    (maphash #'(lambda (key word)
                 (declare (ignore word))
                 (push key names))
             words)
    (setf names (sort names #'string-lessp))
    (format t "~&In word list ~A (~D word~:P):~%  " (dictionary-name dict) (hash-table-count words))
    (loop with column = 2
          for name in names
          do (when (> (+ column (length name) 1) 120)
               (terpri)
               (write-string "  ")
               (setf column 2))
             (write-string name)
             (write-char #\Space)
             (incf column (1+ (length name)))
          finally
             (when (> column 2)
               (terpri)))))

(defmethod search-dictionary ((dict dictionary) name)
  (with-slots (words) dict
    (gethash name words)))

(defmethod forget-word ((dict dictionary) xts word)
  (with-slots (words) dict
    (let ((ordinal (word-ordinal word)))
      (maphash #'(lambda (key a-word)
                   (declare (ignore key))
                   (when (> (word-ordinal a-word) ordinal)
                     (delete-word dict xts a-word)))
               words))
    (delete-word dict xts word)))


;;; Word Lists and the Search Order

(defvar *predefined-words* (make-hash-table :test #'equalp))

(defclass word-lists ()
  ((all-word-lists :initform (make-hash-table :test #'equalp))
   (forth :reader word-lists-forth-word-list :initform nil)
   (search-order :accessor  word-lists-search-order :initform nil)
   (compilation-word-list :accessor word-lists-compilation-word-list :initform nil)
   (next-wid :initform (make-address #xFF 0))
   (wid-to-word-list-map :initform (make-hash-table))
   (next-nt :initform (make-address #xFE 0))
   (nt-to-word-map :initform (make-hash-table))
   (saved-search-order :initform nil)
   (saved-compilation-word-list :initform nil)
   (markers :initform (make-array 0 :fill-pointer 0 :adjustable t))
   (context :initform 0)
   (current :initform 0))
  )

(defmethod initialize-instance :after ((wls word-lists) &key &allow-other-keys)
  (reset-word-lists wls))

(defmethod print-object ((wls word-lists) stream)
  (with-slots (all-word-lists) wls
    (print-unreadable-object (wls stream :type t :identity t)
      (format stream "~D word list~:P" (hash-table-count all-word-lists)))))

(defmethod update-psuedo-state-variables ((wls word-lists))
  (with-slots (search-order compilation-word-list context current) wls
    (setf context (dictionary-wid (first search-order))
          current (dictionary-wid compilation-word-list))))

(defmethod install-predefined-words ((wls word-lists))
  (maphash #'(lambda (forth-name wl-and-word)
               (declare (ignore forth-name))
               (let ((wl (word-list wls (car wl-and-word) :if-not-found :create)))
                 (add-word wl (cdr wl-and-word) :override t :silent t)))
           *predefined-words*))

(defmethod register-predefined-words ((wls word-lists) execution-tokens here)
  (maphash #'(lambda (name wl-and-word)
               (declare (ignore name))
               (register-execution-token execution-tokens (cdr wl-and-word) here))
           *predefined-words*))

(defmethod reset-word-lists ((wls word-lists))
  (with-slots (all-word-lists forth search-order compilation-word-list wid-to-word-list-map nt-to-word-map
               saved-search-order saved-compilation-word-list markers)
      wls
    (clrhash all-word-lists)
    (clrhash wid-to-word-list-map)
    (clrhash nt-to-word-map)
    ;; At a minimum, this will create the FORTH word list
    (install-predefined-words wls)
    (setf forth (word-list wls "FORTH"))
    (if saved-search-order
        (setf search-order (loop for wl in saved-search-order
                                 collect (word-list wls wl :if-not-found :create)))
        (setf search-order (list forth)))
    (if saved-compilation-word-list
        ;; In case the user just creats an empty word list and sets it as the compilation word list before GILDing
        (setf compilation-word-list (word-list wls saved-compilation-word-list :if-not-found :create))
        (setf compilation-word-list forth))
    (setf markers (make-array 0 :fill-pointer 0 :adjustable t))
    (update-psuedo-state-variables wls)))

(defmethod save-word-lists-state ((wls word-lists))
  (with-slots (all-word-lists search-order compilation-word-list saved-search-order saved-compilation-word-list) wls
    (clrhash *predefined-words*)
    (maphash #'(lambda (name dictionary)
                 (maphash #'(lambda (forth-name word)
                              (setf (gethash forth-name *predefined-words*) (cons name word)))
                          (dictionary-words dictionary)))
             all-word-lists)
    (setf saved-search-order (map 'list #'dictionary-name search-order))
    (setf saved-compilation-word-list (dictionary-name compilation-word-list))))

(defmethod word-list ((wls word-lists) name &key (if-not-found :error))
  (with-slots (all-word-lists wid-to-word-list-map next-wid) wls
    (let ((name (or name (gensym "WL"))))
      (or (gethash name all-word-lists)
          (case if-not-found
            (:create
             (let ((word-list (make-instance 'dictionary :name name :wid next-wid :parent wls)))
               (setf (gethash name all-word-lists) word-list
                     (gethash next-wid wid-to-word-list-map) word-list)
               (incf next-wid +cell-size+)
               word-list))
            (:error
             (forth-exception :unknown-word-list "Word list ~A does not exist" name))
            (otherwise nil))))))

(defmethod lookup-wid ((wls word-lists) wid)
  (with-slots (wid-to-word-list-map) wls
    (or (gethash wid wid-to-word-list-map)
        (forth-exception :unknown-word-list "~14,'0X is not a wordlist id" wid))))

(defmethod lookup ((wls word-lists) token)
  (with-slots (search-order) wls
    (loop for dictionary in search-order
            thereis (loop for word = (gethash token (dictionary-words dictionary)) then (word-previous word)
                          while word
                            thereis (and (not (word-smudge? word)) word)))))

(defmethod lookup-nt ((wls word-lists) nt)
  (with-slots (nt-to-word-map) wls
    (or (gethash nt nt-to-word-map)
        (forth-exception :not-a-name-token "~14,'0X is not a name token" nt))))
        
(defmethod also ((wls word-lists))
  (with-slots (search-order) wls
    (push (first search-order) search-order)))

(defmethod definitions ((wls word-lists))
  (with-slots (search-order compilation-word-list) wls
    (setf compilation-word-list (first search-order))
    (update-psuedo-state-variables wls)))

(defmethod only ((wls word-lists))
  (with-slots (search-order forth) wls
    (setf search-order (list forth))
    (update-psuedo-state-variables wls)))

(defmethod previous ((wls word-lists))
  (with-slots (search-order) wls
    (when (< (length search-order) 2)
      (forth-exception :search-order-underflow))
    (pop search-order)
    (update-psuedo-state-variables wls)))

(defmethod vocabulary ((wls word-lists) name)
  (when (word-list wls name :if-not-found nil)
    (forth-exception :duplicate-word-list "~A is the name of an existing word list" name))
  ;; This will create the list as we already verified it doesn't exist
  (word-list wls name :if-not-found :create))

(defmethod replace-top-of-search-order ((wls word-lists) (dict dictionary))
  (with-slots (search-order) wls
    (setf (first search-order) dict)
    (update-psuedo-state-variables wls)))

(defmethod replace-top-of-search-order ((wls word-lists) (wid integer))
  (with-slots (search-order wid-to-word-list-map) wls
    (let ((word-list (gethash wid wid-to-word-list-map)))
      (if word-list
          (replace-top-of-search-order wls word-list)
          (forth-exception :unknown-word-list "~14,'0X is not a wordlist id" wid)))))

(defmethod traverse-wordlist ((wls word-lists) wl function)
  (maphash #'(lambda (name word)
               (declare (ignore name))
               (if (funcall function (word-name-token word))
                   (loop for old = (word-previous word) then (word-previous old)
                         while old
                         do (when (eq (word-parent old) wl)
                              (unless (funcall function (word-name-token old))
                                (return-from traverse-wordlist))))
                   (return-from traverse-wordlist)))
           (dictionary-words wl)))


;;; Words

(defclass word ()
  ((name :accessor word-name :initarg :name)
   (previous :accessor word-previous :initarg :previous :initform nil)
   (smudge? :accessor word-smudge? :initarg :smudge? :initform nil)
   (immediate? :accessor word-immediate? :initarg :immediate? :initform nil)
   (compile-only? :accessor word-compile-only? :initarg :compile-only? :initform nil)
   (inlineable? :accessor word-inlineable? :initarg :inlineable? :initform nil)
   (creating-word? :accessor word-creating-word? :initarg :creating-word? :initform nil)
   (deferring-word? :accessor word-deferring-word? :initarg :deferring-word? :initform nil)
   (code :accessor word-code :initarg :code :initform nil)
   (inline-forms :accessor word-inline-forms :initarg :inline-forms :initform nil)
   (parameters :accessor word-parameters :initarg :parameters :initform nil)
   (does> :accessor word-does> :initform nil)
   (parent :accessor word-parent :initform nil)
   (execution-token :accessor word-execution-token :initform nil)
   (compile-token :accessor word-compile-token :initform nil)
   (name-token :accessor word-name-token :initform nil)
   (ordinal :accessor word-ordinal :initform 0))
  )

(defmethod print-object ((word word) stream)
  (print-unreadable-object (word stream :type t :identity t)
    (write-string (or (word-name word) "<Anonymous>") stream)))

(defmacro define-word (name (&key (word-list "FORTH") ((:word forth-name) (symbol-name name))
                                  immediate? compile-only? (inlineable? (not compile-only?)))
                       &body body)
  (let* ((word (gensym))
         (body (loop with forms = (copy-list body)
                     while (stringp (car forms))
                     do (pop forms)
                     finally (return forms)))
         (thunk `(ccl:nfunction ,(intern forth-name *forth-words-package*)
                   (lambda (fs &rest parameters)
                     (declare (ignorable parameters))
                     (with-forth-system (fs)
                       ,@body)))))
    `(eval-when (:load-toplevel :execute)
       (let ((,word (make-instance 'word
                                   :name ,forth-name
                                   :immediate? ,immediate?
                                   :compile-only? ,compile-only?
                                   :inlineable? ,inlineable?
                                   :code ,thunk
                                   :inline-forms ',(when inlineable?
                                                     (reverse body)))))
         (setf (gethash ,forth-name *predefined-words*) (cons ,word-list ,word))))))

(defmacro define-state-word (slot &key (word-list "FORTH") ((:word forth-name) (symbol-name slot)) immediate? compile-only?)
  (let ((description (format nil "Place the address of ~A on the stack" forth-name)))
    `(define-word ,slot (:word-list ,word-list :word ,forth-name :immediate? ,immediate? :compile-only? ,compile-only?)
       "( - a-addr )"
       ,description
       (stack-push data-stack (state-slot-address memory ',slot)))))

(defun make-word (name code &key smudge? immediate? compile-only? creating-word? deferring-word? parameters)
  (make-instance 'word :name name
                       :code code
                       :smudge? smudge?
                       :immediate? immediate?
                       :compile-only? compile-only?
                       :creating-word? creating-word?
                       :deferring-word? deferring-word?
                       :parameters (copy-list parameters)))

(defmethod forget ((word word) xts)
  (forget-word (word-parent word) xts word))


;;; MARKER support

(defclass marker ()
  ((search-order :reader marker-search-order :initarg :search-order :initform nil)
   (compilation-word-list :reader marker-compilation-word-list :initarg :compilation-word-list :initform nil)
   (words :initform nil)
   (included-files :initform nil))
  )

(defmethod add-word-to-marker ((marker marker) word)
  (with-slots (words) marker
    (push word words)))

(defmethod remove-words ((marker marker) xts)
  (with-slots (words) marker
    (map  nil #'(lambda (word) (delete-word (word-parent word) xts word)) words)
    (setf words nil)))

(defmethod add-included-file-to-marker ((marker marker) included-file)
  (with-slots (included-files) marker
    (push included-file included-files)))

(defmethod remove-included-files ((marker marker) files)
  (with-slots (included-files) marker
    (map nil #'(lambda (included-file) (forget-included-file files included-file)) included-files)
    (setf included-files nil)))

(defmethod register-marker ((wls word-lists))
  (with-slots (search-order compilation-word-list markers) wls
    (let ((marker (make-instance 'marker :search-order (copy-list search-order) :compilation-word-list compilation-word-list)))
      (vector-push-extend marker markers)
      marker)))

(defmethod execute-marker ((wls word-lists) xts files (marker marker))
  (with-slots (search-order compilation-word-list markers) wls
    (let ((position (position marker markers)))
      ;; Ignore stale markers
      (when position
        (setf search-order (copy-list (marker-search-order marker))
              compilation-word-list (marker-compilation-word-list marker))
        (remove-words marker xts)
        (remove-included-files marker files)
        (loop for i from position below (fill-pointer markers)
              do (setf (aref markers i) nil))
        (setf (fill-pointer markers) position)))))

(defmethod note-new-word ((wls word-lists) (dict dictionary) (word word))
  (with-slots (next-nt nt-to-word-map markers) wls
    (setf (word-parent word) dict
          (word-name-token word) next-nt
          (gethash next-nt nt-to-word-map) word)
    (incf next-nt +cell-size+)
    (map nil #'(lambda (marker) (add-word-to-marker marker word)) markers)))

(defmethod note-new-included-file ((wls word-lists) truename)
  (with-slots (markers) wls
    (map nil #'(lambda (marker) (add-included-file-to-marker marker truename)) markers)))
