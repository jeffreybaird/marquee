Mox.defmock(Bobine.Content.MockMuxClient,
  for: Bobine.Content.MuxClientBehaviour
)

Mox.defmock(Bobine.Billing.MockStripeClient,
  for: Bobine.Billing.StripeClientBehaviour
)

Mox.defmock(Bobine.Storage.MockSpacesClient,
  for: Bobine.Storage.SpacesClientBehaviour
)

Mox.defmock(Bobine.Podcasts.MockRemoteFeedClient,
  for: Bobine.Podcasts.RemoteFeedClient
)
