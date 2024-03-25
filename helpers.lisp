(in-package #:forth)

;;; Functions used as the code for some of the words defined by Forth 2012

(defun push-parameter-as-cell (fs &rest parameters)
  (with-forth-system (fs)
    (stack-push data-stack (first parameters))))

(defun push-parameter-as-double-cell (fs &rest parameters)
  (with-forth-system (fs)
    (stack-push-double data-stack (first parameters))))

(defun push-value (fs &rest parameters)
  (with-forth-system (fs)
    (let ((address (first parameters))
          (type (second parameters)))
      (case type
        (:value
         (stack-push data-stack (memory-cell memory address)))
        (:2value
         (stack-push-double data-stack (memory-double-cell memory address)))
        (:fvalue
         (stack-push float-stack (memory-native-float memory address)))))))

(defun push-parameter-as-float (fs &rest parameters)
  (with-forth-system (fs)
    (stack-push float-stack (first parameters))))

(defun execute-parameter (fs &rest parameters)
  (with-forth-system (fs)
    (when (null (first parameters))
      (forth-exception :defer-not-set))
    (execute execution-tokens (first parameters) fs)))

(defun do-marker (fs &rest parameters)
  (with-forth-system (fs)
    (execute-marker word-lists execution-tokens files (first parameters))))

(defun replace-top-of-search-order-with-parameter (fs &rest parameters)
  (with-forth-system (fs)
    (replace-top-of-search-order word-lists (first parameters))))

;;;

(defstruct (forth-structure (:conc-name #:fs-))
  (size 0)
  (word nil)
  (fields nil))

(defun push-structure-size-from-parameter (fs &rest parameters)
  (with-forth-system (fs)
    (stack-push data-stack (fs-size (first parameters)))))

(defun push-field-address-from-parameter (fs &rest parameters)
  (with-forth-system (fs)
    (stack-push data-stack (+ (stack-pop data-stack) (first parameters)))))

