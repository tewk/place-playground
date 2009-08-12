#lang scheme
(require (prefix-in p: "places.ss"))
(provide echo)

(define (echo ch)
  (let ((msg (p:recv ch)))
    (match msg
      [(struct p:new-channel-mesg (nch innermsg))
       (p:log (format "got new-channel-mesg ~a ~a~n" nch innermsg))
       (p:send nch (p:recv nch))]
      [_ 
       (p:log (format "sending ~a~n" msg)) (p:send ch msg)]))
  (echo ch))