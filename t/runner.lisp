(in-package #:hpack-codec/test)

(defun run-tests ()
  (unless (run-all :reporter :spec :pass-with-no-tests nil)
    (error "cl-hpack-codec-kit tests failed."))
  t)
