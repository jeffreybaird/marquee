import type { HooksOptions } from "phoenix_live_view"

import AnalyticsChart from "./analytics_chart_hook"
import CardFocus from "./card_focus"
import Carousel from "./carousel"
import ChatAutoScroll from "./chat_auto_scroll"
import CopyToClipboard from "./copy_to_clipboard"
import GuidedTour from "./guided_tour"
import HeroCarousel from "./hero_carousel"
import MuxPlayer from "./mux_player"
import MuxUploader from "./mux_uploader"
import PageTour from "./page_tour"
import QueueSortable from "./queue_sortable"
import RowScroller from "./row_scroller"
import ScrollToCurrentEpisode from "./scroll_to_current_episode"
import SpacesUploader from "./spaces_uploader"
import StaggerReveal from "./stagger_reveal"
import ViewerNav from "./viewer_nav"

export const hooks = {
  AnalyticsChart,
  CardFocus,
  Carousel,
  ChatAutoScroll,
  CopyToClipboard,
  GuidedTour,
  HeroCarousel,
  MuxPlayer,
  MuxUploader,
  PageTour,
  QueueSortable,
  RowScroller,
  ScrollToCurrentEpisode,
  SpacesUploader,
  StaggerReveal,
  ViewerNav,
} satisfies HooksOptions
