(in-package #:asdf-user)

(asdf:defsystem "cl-hpack-codec-kit"
  :description "RFC 7541 Huffman and prefixed-integer codecs, shared by HPACK and QPACK."
  :author "nerima-lisp"
  :license "MIT"
  :version "0.1.0"
  :depends-on ()
  :pathname "src"
  :serial t
  :components ((:file "package")
               (:file "conditions")
               (:file "huffman-tables")
               (:file "huffman")
               (:file "integer"))
  :in-order-to ((test-op (test-op "cl-hpack-codec-kit/test"))))

(asdf:defsystem "cl-hpack-codec-kit/test"
  :description "Tests for cl-hpack-codec-kit."
  :depends-on ("cl-hpack-codec-kit" "cl-weave")
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "tests-integer")
               (:file "tests-huffman")
               (:file "runner"))
  :perform (asdf:test-op (op c)
             (declare (ignore op c))
             (uiop:symbol-call "HPACK-CODEC/TEST" "RUN-TESTS")))
