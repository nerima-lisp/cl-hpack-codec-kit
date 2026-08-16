(in-package #:hpack-codec)

(defun %hpack-proper-list-p (object)
  (loop with slow = object
        with fast = object
        do (cond
             ((null fast)
              (return t))
             ((not (consp fast))
              (return nil))
             (t
              (setf fast (cdr fast))
              (when (null fast)
                (return t))
              (when (not (consp fast))
                (return nil))
              (setf fast (cdr fast)
                    slow (cdr slow))
              (when (eq slow fast)
                (return nil))))))

(defun %hpack-header-sequence (headers)
  (cond
    ((null headers) nil)
    ((vectorp headers)
     (loop for header across headers collect header))
    ((%hpack-proper-list-p headers) headers)
    (t
     (%hpack-block-error
      "HPACK headers must be a proper list or vector."
      :hpack-header-block
      headers))))
