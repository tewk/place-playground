#lang racket
(require (prefix-in p: "places.ss"))
(provide echo)

(define (echo ch)
  (let ((msg (p:place-channel-recv ch)))
    (match msg
      [(struct p:new-channel-mesg (nch innermsg))
       (p:log (format "got new-channel-mesg ~a ~a~n" nch innermsg))
       (p:place-channel-send nch (p:place-channel-recv nch))]
      [_ 
       (p:log (format "sending ~a~n" msg)) (p:place-channel-send ch msg)]))
  (echo ch))
