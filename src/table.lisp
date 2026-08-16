(in-package #:hpack-codec)

(defconstant +hpack-static-table-size+ 61)

(defun %table-error (message &optional detail)
  (error 'hpack-codec-error
         :message message
         :operation :table
         :detail detail))

(defun %ensure-nonnegative-integer (value description)
  (unless (and (integerp value) (<= 0 value))
    (%table-error (format nil "~A must be a non-negative integer." description)
                  value))
  value)

(defun %ensure-table-size (value description)
  (%ensure-nonnegative-integer value description)
  (when (> value #xffffffff)
    (%table-error (format nil "~A exceeds the HPACK table-size limit." description)
                  value))
  value)

(defun %ensure-octet-vector (value description)
  (unless (vectorp value)
    (%table-error (format nil "~A must be an octet vector." description)
                  value))
  (loop for octet across value
        unless (and (integerp octet) (<= 0 octet 255))
          do (%table-error
              (format nil "~A must contain only octets." description)
              octet))
  value)

(defun %copy-octets (octets)
  (let ((copy (make-array (length octets)
                          :element-type '(unsigned-byte 8))))
    (replace copy octets)
    copy))

(defun %ascii-octets (string)
  (let ((octets (make-array (length string)
                           :element-type '(unsigned-byte 8))))
    (loop for index below (length string)
          for code = (char-code (char string index))
          do (when (> code 127)
               (%table-error "Static table text must contain ASCII characters."
                             string))
             (setf (aref octets index) code))
    octets))

(defstruct (hpack-table-entry
             (:constructor %make-hpack-table-entry ())
             (:copier nil))
  (name nil)
  (value nil))

(defun %make-table-entry (name value)
  (let ((entry (%make-hpack-table-entry)))
    (setf (hpack-table-entry-name entry) name
          (hpack-table-entry-value entry) value)
    entry))

(defun %copy-table-entry (entry)
  (%make-table-entry (%copy-octets (hpack-table-entry-name entry))
                     (%copy-octets (hpack-table-entry-value entry))))

(defun %table-entry-size (entry)
  (unless (hpack-table-entry-p entry)
    (%table-error "Value must be an HPACK table entry." entry))
  (+ 32
     (length (hpack-table-entry-name entry))
     (length (hpack-table-entry-value entry))))

(defparameter *hpack-static-table*
  (map 'vector
       (lambda (entry)
         (%make-table-entry (%ascii-octets (first entry))
                            (%ascii-octets (second entry))))
       '((":authority" "")
         (":method" "GET")
         (":method" "POST")
         (":path" "/")
         (":path" "/index.html")
         (":scheme" "http")
         (":scheme" "https")
         (":status" "200")
         (":status" "204")
         (":status" "206")
         (":status" "304")
         (":status" "400")
         (":status" "404")
         (":status" "500")
         ("accept-charset" "")
         ("accept-encoding" "gzip, deflate")
         ("accept-language" "")
         ("accept-ranges" "")
         ("accept" "")
         ("access-control-allow-origin" "")
         ("age" "")
         ("allow" "")
         ("authorization" "")
         ("cache-control" "")
         ("content-disposition" "")
         ("content-encoding" "")
         ("content-language" "")
         ("content-length" "")
         ("content-location" "")
         ("content-range" "")
         ("content-type" "")
         ("cookie" "")
         ("date" "")
         ("etag" "")
         ("expect" "")
         ("expires" "")
         ("from" "")
         ("host" "")
         ("if-match" "")
         ("if-modified-since" "")
         ("if-none-match" "")
         ("if-range" "")
         ("if-unmodified-since" "")
         ("last-modified" "")
         ("link" "")
         ("location" "")
         ("max-forwards" "")
         ("proxy-authenticate" "")
         ("proxy-authorization" "")
         ("range" "")
         ("referer" "")
         ("refresh" "")
         ("retry-after" "")
         ("server" "")
         ("set-cookie" "")
         ("strict-transport-security" "")
         ("transfer-encoding" "")
         ("user-agent" "")
         ("vary" "")
         ("via" "")
         ("www-authenticate" ""))))

(unless (= (length *hpack-static-table*) +hpack-static-table-size+)
  (%table-error "The HPACK static table must contain exactly 61 entries."))

(defun hpack-static-table-count ()
  (length *hpack-static-table*))

(defun hpack-static-table-entry (index)
  (%ensure-nonnegative-integer index "Static table index")
  (unless (<= 1 index +hpack-static-table-size+)
    (%table-error "Static table index is out of range." index))
  (%copy-table-entry (aref *hpack-static-table* (1- index))))

(defun hpack-static-table ()
  (map 'vector #'%copy-table-entry *hpack-static-table*))

(defstruct (hpack-table
             (:constructor %allocate-hpack-table ())
             (:copier nil)
             (:conc-name %hpack-table-))
  (maximum-size 4096)
  (size 0)
  (entries nil))

(defun %parse-table-size-arguments (arguments)
  (cond
    ((null arguments)
     4096)
    ((and (= (length arguments) 1)
          (not (keywordp (first arguments))))
     (first arguments))
    ((and (evenp (length arguments))
          (keywordp (first arguments)))
     (let ((maximum-size 4096)
           (remaining arguments)
           (seen nil))
       (loop while remaining
             do (let ((key (pop remaining))
                      (value (pop remaining)))
                  (case key
                    ((:maximum-size :max-size)
                     (when seen
                       (%table-error
                        "A table size option was supplied more than once."
                        key))
                     (setf seen t
                           maximum-size value))
                    (otherwise
                     (%table-error "Unknown table size option." key)))))
       maximum-size))
    (t
     (%table-error "Table size arguments are invalid." arguments))))

(defun make-hpack-table (&rest arguments)
  (let ((maximum-size
          (%ensure-table-size
           (%parse-table-size-arguments arguments)
           "Table maximum size")))
    (let ((table (%allocate-hpack-table)))
      (setf (%hpack-table-maximum-size table) maximum-size)
      table)))

(defun %ensure-table (table)
  (unless (hpack-table-p table)
    (%table-error "Value must be an HPACK dynamic table." table))
  table)

(defun %clear-table (table)
  (setf (%hpack-table-entries table) nil
        (%hpack-table-size table) 0)
  table)

(defun hpack-table-size (table)
  (%ensure-table table)
  (%hpack-table-size table))

(defun hpack-table-current-size (table)
  (hpack-table-size table))

(defun hpack-table-maximum-size (table)
  (%ensure-table table)
  (%hpack-table-maximum-size table))

(defun hpack-table-count (table)
  (%ensure-table table)
  (length (%hpack-table-entries table)))

(defun %evict-oldest (table)
  (let ((entries (%hpack-table-entries table)))
    (when entries
      (let* ((oldest (car (last entries)))
             (remaining (butlast entries)))
        (setf (%hpack-table-entries table) remaining)
        (decf (%hpack-table-size table) (%table-entry-size oldest))
        oldest))))

(defun hpack-table-evict-oldest (table)
  (%ensure-table table)
  (let ((entry (%evict-oldest table)))
    (and entry (%copy-table-entry entry))))

(defun hpack-table-evict (table &optional (count 1))
  (%ensure-table table)
  (%ensure-nonnegative-integer count "Eviction count")
  (loop repeat count
        do (unless (%evict-oldest table)
             (return table))
        finally (return table)))

(defun %evict-to-size (table target-size)
  (loop while (> (%hpack-table-size table) target-size)
        do (%evict-oldest table))
  table)

(defun hpack-table-evict-to-size (table target-size)
  (%ensure-table table)
  (%ensure-nonnegative-integer target-size "Target table size")
  (%evict-to-size table target-size))

(defun hpack-table-update-maximum-size (table maximum-size)
  (%ensure-table table)
  (%ensure-table-size maximum-size "Table maximum size")
  (setf (%hpack-table-maximum-size table) maximum-size)
  (%evict-to-size table maximum-size))

(defun hpack-table-set-maximum-size (table maximum-size)
  (hpack-table-update-maximum-size table maximum-size))

(defun hpack-table-insert (table name &optional (value nil value-supplied-p))
  (%ensure-table table)
  (let ((entry
          (if (hpack-table-entry-p name)
              (progn
                (when value-supplied-p
                  (%table-error "An entry insertion cannot have a separate value."))
                (%copy-table-entry name))
              (progn
                (%ensure-octet-vector name "Table entry name")
                (%ensure-octet-vector value "Table entry value")
                (%make-table-entry (%copy-octets name) (%copy-octets value))))))
    (let ((entry-size (%table-entry-size entry)))
      (if (> entry-size (%hpack-table-maximum-size table))
          (%clear-table table)
          (progn
            (%evict-to-size table
                            (- (%hpack-table-maximum-size table) entry-size))
            (push entry (%hpack-table-entries table))
            (incf (%hpack-table-size table) entry-size))))
  table))

(defun %valid-table-index-p (table index)
  (and (integerp index)
       (<= 1 index)
       (<= index (+ +hpack-static-table-size+
                    (length (%hpack-table-entries table))))))

(defun hpack-table-lookup (table index)
  (%ensure-table table)
  (unless (integerp index)
    (%table-error "Table index must be an integer." index))
  (unless (%valid-table-index-p table index)
    (%table-error "Table index is out of range." index))
  (if (<= index +hpack-static-table-size+)
      (%copy-table-entry (aref *hpack-static-table* (1- index)))
      (%copy-table-entry
       (nth (- index (1+ +hpack-static-table-size+))
            (%hpack-table-entries table)))))

(defun hpack-table-entry (table index)
  (hpack-table-lookup table index))

(defun %entry-matches-p (entry name value)
  (and (equalp (hpack-table-entry-name entry) name)
       (equalp (hpack-table-entry-value entry) value)))

(defun %entry-name-matches-p (entry name)
  (equalp (hpack-table-entry-name entry) name))

(defun hpack-table-find-exact (table name value)
  (%ensure-table table)
  (%ensure-octet-vector name "Lookup name")
  (%ensure-octet-vector value "Lookup value")
  (or (loop for index from 1 to +hpack-static-table-size+
            for entry = (aref *hpack-static-table* (1- index))
            when (%entry-matches-p entry name value)
              return index)
      (loop for entry in (%hpack-table-entries table)
            for index from (1+ +hpack-static-table-size+)
            when (%entry-matches-p entry name value)
              return index)))

(defun hpack-table-find-name (table name)
  (%ensure-table table)
  (%ensure-octet-vector name "Lookup name")
  (or (loop for index from 1 to +hpack-static-table-size+
            for entry = (aref *hpack-static-table* (1- index))
            when (%entry-name-matches-p entry name)
              return index)
      (loop for entry in (%hpack-table-entries table)
            for index from (1+ +hpack-static-table-size+)
            when (%entry-name-matches-p entry name)
              return index)))

(defun hpack-table-copy (table)
  (%ensure-table table)
  (let ((copy (%allocate-hpack-table)))
    (setf (%hpack-table-maximum-size copy) (%hpack-table-maximum-size table)
          (%hpack-table-size copy) (%hpack-table-size table)
          (%hpack-table-entries copy)
          (mapcar #'%copy-table-entry (%hpack-table-entries table)))
    copy))
