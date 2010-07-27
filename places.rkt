#lang racket
(require racket/system
 racket/async-channel
 racket/serialize
 racket/runtime-path
 mzlib/os)

;places prototype
;places are modelled as processes
;multiplexed-channel serves as a backbone channel between process
;pchannels are the channels processe actually use to communicate


(provide
  place
  place-wait
  place-kill
  place-channel
  place-channel-recv
  place-channel-send
  (struct-out new-channel-mesg)
  place-channel-send/recv
  
  ;internal
  place-child
  place-vchannel
  log)


(define (say x) (printf "~a~n" x))

(define-struct place-s (pid ch subprocess-obj err))

(define (place-kill pl) (subprocess-kill (place-s-subprocess-obj pl) #t))

(define (place-wait pl)
  (let ((spo (place-s-subprocess-obj pl)))
    (subprocess-wait spo)
    (subprocess-status spo)))

(define (place-channel-send/recv ch x)
  (place-channel-send ch x)
  (place-channel-recv ch))

(define LH #f)
(define (log msg)
  (when (not LH)
    (set! LH (open-output-file (format "~aLOG" (getpid)) #:exists 'truncate/replace)))
  (fprintf LH "~a" msg)
  (flush-output LH))

(define-serializable-struct mkmuxchannelmsg (myid otherid))
(define-serializable-struct muxchannelmsg (destid msg))
(define-serializable-struct mkvchannelmsg (myid otherid msg))
(define-serializable-struct new-channel-mesg (ch msg))
(define-serializable-struct new-child-mesg (module-name func-name))
(define-struct start-child-msg (in out comch))
(define-struct start-parent-msg (in out err comch))
(define-struct start-vchannel-msg (ch1 msg1 ch2 msg2 comch))

;=========================== pumper thread ==========================

(define pump #f)
(define (start-pump)
  (define lastchid 0)
  (define (new-channel-id)
    (let ((newid lastchid))
      (set! lastchid (+ 1 lastchid))
      (format "~a_~a" (getpid) newid)))
  
  (define id-to-ch (make-hash))
  (define ch-to-id (make-hash))
  (define evtlst (list))
  (define (add-event x) (set! evtlst (cons x evtlst)))
  
  (define (reg-endpoint muxch myid otherid ch)
    (hash-set! id-to-ch myid ch)
    (hash-set! ch-to-id ch myid)
    (add-event (wrap-evt (pchannel-in ch) (λ (x)
                                            (log (format "phannel ~a received ~a sending to otherid ~a~n" myid x otherid))
                                            (multiplexed-channel-send-to-id muxch otherid 
                                                                            (match x 
                                                                              [(? pchannel?)
                                                                               (let* ((id1 (new-channel-id))
                                                                                      (id2 (new-channel-id)))
                                                                                 (reg-endpoint muxch id1 id2 x)
                                                                                 (log (format "sending to otherid ~a mkvchannelmsg ~a ~a~n" otherid id2 id1))
                                                                                 (make-mkvchannelmsg id2 id1 #f))]
                                                                              [ _ x])))))
    ch)
  
  
  (define (mk-local-endpoint muxch myid otherid)
    (let* ((ch (place-channel)))
      (reg-endpoint muxch myid otherid ch)))
  
  (define (forward-message destid msg)
    (let ((destch (hash-ref id-to-ch destid)))
      (cond 
        [(pchannel? destch) 
         (log (format "message delivery to pchannel ~a ~a~n" destid msg))
         (i_pchansend destch msg)]
        [(multiplexed-channel? destch) 
         (log (format "message fowarding ~a ~a~n" destid msg))
         (multiplexed-channel-send-to-id destch destid msg)]
        [else (log (format "message fowarding failed ~a ~a ~a~n" destid destch msg))])))
  
  (define (recv-process-muxch-message muxch)
    (process-muxch-message muxch (multiplexed-channel-recv muxch)))
  (define (process-muxch-message muxch muxmsg)
    (match muxmsg
      [(struct mkmuxchannelmsg (myid otherid)) 
       (log (format "process mkmuxchannelmsg ~a ~a~n" myid otherid))          
       
       (mk-local-endpoint muxch myid otherid)]
      [(struct muxchannelmsg (destid msg)) 
       (match msg
         [(struct mkvchannelmsg (myid otherid innermsg))
          (log (format "process mkvchannelmsg ~a ~a ~a~n" myid otherid innermsg))          
          (let ((destch (hash-ref id-to-ch destid)))
            (match destch
              [(? pchannel?) 
               (log (format "mkvchannelmsg destination ~a ~a ~a~n" myid otherid innermsg))
               (i_pchansend destch (make-new-channel-mesg (mk-local-endpoint muxch myid otherid) innermsg))]
              [(? multiplexed-channel?)
               (log (format "mkvchannelmsg inner hop ~a ~a ~a~n" myid otherid innermsg))
               (hash-set! id-to-ch otherid muxch)
               (hash-set! id-to-ch myid destch)
               (multiplexed-channel-send-to-id destch destid msg)]))]
         
         [else (forward-message destid msg)])]
      [else ((raise (format "~a not exepcted ~n" muxmsg)))]))
  
  ;pump control channel
  (define reg-evt-ch (make-async-channel))
  (add-event (wrap-evt reg-evt-ch (λ (msg)
                                    (log (format "pump received ~a~n" msg))
                                    (match msg 
                                      [(struct start-child-msg (in out comch))
                                       (let* ((muxch (make-multiplexed-channel in out))
                                              (ch (recv-process-muxch-message muxch)))
                                         (log (format "starting child pump~n"))
                                         (add-event (wrap-evt in (λ (x) 
                                                                   (log (format "childmux received "))
                                                                   (recv-process-muxch-message muxch))))
                                         (channel-put comch ch))]
                                      
                                      [(struct start-parent-msg (in out err comch))
                                       (let* ((muxch (make-multiplexed-channel in out))
                                              (pl1id (new-channel-id))
                                              (pl2id (new-channel-id))
                                              (ch (process-muxch-message muxch (make-mkmuxchannelmsg pl1id pl2id))))
                                         (log (format "starting parent pump~n"))
                                         (multiplexed-channel-send muxch (make-mkmuxchannelmsg pl2id pl1id))
                                         (add-event (wrap-evt in (λ (x)
                                                                   (log (format "parentmux received "))
                                                                   (recv-process-muxch-message muxch))))
                                         (add-event (wrap-evt err (λ (x)
                                                                    (let* ((buf (make-bytes 1024))
                                                                           (bytesread (read-bytes-avail! buf err)))
                                                                      (if (eq? eof bytesread)
                                                                          (log (format "~a send eof on stderr~n" pl2id))
                                                                          (log (format "STDERr ~a ~a" pl2id (bytes->string/latin-1 buf #f 0 bytesread))))))))
                                         (channel-put comch ch))]
                                      
                                      [(struct start-vchannel-msg (ch1 msg1 ch2 msg2 comch))
                                       (let* ((id1 (new-channel-id))
                                              (id2 (new-channel-id)))
                                         (multiplexed-channel-send-to-id (hash-ref ch-to-id ch1) (make-mkvchannelmsg id1 id2 msg1))
                                         (multiplexed-channel-send-to-id (hash-ref ch-to-id ch2) (make-mkvchannelmsg id2 id1 msg2))
                                         (channel-put comch #t))]))))
  
  ;start pump thread
  (thread (λ () 
            (let loop ()
              (apply sync evtlst)
              (loop))))
  
  reg-evt-ch)


(define (register-mux-with-pump msg)
  (when (not pump)
    (set! pump (start-pump)))
  (async-channel-put pump msg))

(define (kill-pump)
  (when (pump)
    (kill-thread pump)))

(define (place-vchannel ch1 msg1 ch2 msg2) 
  (let ((comch (make-channel)))
    (register-mux-with-pump (make-start-vchannel-msg ch1 msg1 ch2 msg2 comch))
    (channel-get comch)))

(define (register-place cout cin cerr)
  (let ((comch (make-channel)))
    (register-mux-with-pump (make-start-parent-msg cout cin cerr comch))
    (channel-get comch)))

(define (register-child in out)
  (let ((comch (make-channel)))
    (register-mux-with-pump (make-start-child-msg in out comch))
    (channel-get comch)))

;========================== pchannel
(define-struct pchannel (in out))
(define (place-channel) (make-pchannel (make-async-channel) (make-async-channel)))
(define (resolve->channel o)
  (match o
    [(? place-s? p) (place-s-ch p)]
    [(? pchannel? p) p]))
(define (place-channel-send ch x)     (async-channel-put (pchannel-in  (resolve->channel ch)) x))
(define (place-channel-recv ch)       (async-channel-get (pchannel-out (resolve->channel ch))))
(define (i_pchansend ch x)            (async-channel-put (pchannel-out ch) x))
(define (i_pchanrecv ch)              (async-channel-get (pchannel-in ch)))

;=========================== multiplexed-channel
(define-struct multiplexed-channel (in out))

(define (multiplexed-channel-send ch x)
  (let ((out (multiplexed-channel-out ch)))
    (write (serialize x) out)
    (flush-output out)))

(define (multiplexed-channel-send-to-id muxch id x)
  (multiplexed-channel-send muxch (make-muxchannelmsg id x)))

(define (multiplexed-channel-recv ch)
  (deserialize (read (multiplexed-channel-in ch))))


;=========================== create-place
(define-runtime-path places-ss-path "places.ss")

(define (place module-name func-name)
  (let-values ([(sp out in err)
      (subprocess #f #f #f (find-system-path 'exec-file) "-e" "(eval(read))")])
    (write `((dynamic-require (bytes->path ,(path->bytes places-ss-path)) (quote place-child))) in)
    (let ([pl (make-place-s (subprocess-pid sp) (register-place out in err) sp err)])
      (place-channel-send pl (make-new-child-mesg module-name func-name))
      pl)))

(define (place-child)
  (let* ((ch (register-child (current-input-port) (current-output-port)))
         (msg (place-channel-recv ch)))
    (match msg
      [(struct new-child-mesg (module-name func-name)) ((dynamic-require module-name (string->symbol func-name)) ch)]
      [_ (raise (format "Place child expected new-child-mesg got ~a~n" msg))])))