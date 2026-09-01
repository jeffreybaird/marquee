Mox.defmock(Marquee.Content.MockMuxClient,
  for: Marquee.Content.MuxClientBehaviour
)

Mox.defmock(Marquee.Billing.MockStripeClient,
  for: Marquee.Billing.StripeClientBehaviour
)

Mox.defmock(Marquee.Storage.MockSpacesClient,
  for: Marquee.Storage.SpacesClientBehaviour
)

Mox.defmock(Marquee.Podcasts.MockRemoteFeedClient,
  for: Marquee.Podcasts.RemoteFeedClient
)
