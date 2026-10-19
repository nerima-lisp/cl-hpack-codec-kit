(in-package #:hpack-codec)

(defstruct (hpack-header
            (:constructor %make-hpack-header (name value representation)))
  name
  value
  representation)

(defstruct (hpack-encoder
            (:constructor %make-hpack-encoder
                (&key table maximum-table-size pending-minimum-table-size
                      pending-final-table-size huffman maximum-block-size
                      maximum-header-list-size maximum-field-count
                      maximum-string-length)))
  table
  maximum-table-size
  pending-minimum-table-size
  pending-final-table-size
  huffman
  maximum-block-size
  maximum-header-list-size
  maximum-field-count
  maximum-string-length)

(defstruct (hpack-decoder
            (:constructor %make-hpack-decoder
                (&key table maximum-table-size maximum-block-size
                      maximum-header-list-size maximum-field-count
                      maximum-string-length validate-header-names
                      pending-octets)))
  table
  maximum-table-size
  maximum-block-size
  maximum-header-list-size
  maximum-field-count
  maximum-string-length
  validate-header-names
  pending-octets)
