(in-package #:asdf-user)

(asdf:defsystem "cl-hpack-codec-kit"
  :description "RFC 7541 HPACK header compression codec."
  :author "nerima-lisp"
  :license "MIT"
  :version "1.1.0"
  :depends-on ()
  :pathname "src"
  :serial t
  :components ((:file "package")
               (:file "conditions")
               (:file "huffman-tables")
               (:file "huffman")
               (:file "integer")
               (:file "table")
               (:file "model")
               (:file "block-core")
               (:file "decoder-model")
               (:file "encoder-model")
               (:file "encoder-sequence")
               (:file "encoder-normalize-header")
               (:file "encoder-normalize-headers")
               (:file "encoder-representation")
               (:file "encoder-block")
               (:file "decoder"))
  :in-order-to ((test-op (test-op "cl-hpack-codec-kit/test"))))

(asdf:defsystem "cl-hpack-codec-kit/test"
  :description "Tests for cl-hpack-codec-kit."
  :depends-on ("cl-hpack-codec-kit" "cl-weave")
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "tests-integer")
               (:file "tests-huffman")
               (:file "tests-hpack")
               (:file "runner"))
  :perform (asdf:test-op (op c)
             (declare (ignore op c))
             (uiop:symbol-call "HPACK-CODEC/TEST" "RUN-TESTS")))
