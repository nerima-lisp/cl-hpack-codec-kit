(defpackage #:hpack-codec/test
  (:use #:cl #:hpack-codec)
  (:shadowing-import-from #:cl-weave
                          #:describe)
  (:import-from #:cl-weave
                #:expect
                #:it
                #:run-all
                #:signals)
  (:export #:run-tests))

(in-package #:hpack-codec/test)

(defun octets (&rest values)
  (make-array (length values)
              :element-type '(unsigned-byte 8)
              :initial-contents values))

(defun ascii (string)
  (map '(vector (unsigned-byte 8)) #'char-code string))
