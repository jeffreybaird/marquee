defmodule Marquee.AdminDemoGeometry do
  @moduledoc "Browser-only geometry assertions for private-demo viewer chrome."
  import ExUnit.Assertions

  def assert_separated(browser) do
    Wallaby.Browser.execute_script(
      browser,
      """
      window.scrollTo(0,0);
      const el=n=>document.querySelector('[data-test="'+n+'"]');
      const rect=e=>{const r=e.getBoundingClientRect();return {top:r.top,bottom:r.bottom,height:r.height}};
      const nav=el('sv-nav'), main=document.querySelector('[data-test=sv-root] main');
      const canvas=document.createElement('canvas');canvas.width=canvas.height=1;const ctx=canvas.getContext('2d');ctx.fillStyle=getComputedStyle(nav).backgroundColor;ctx.fillRect(0,0,1,1);
      const hit=n=>{const e=el(n),r=e.getBoundingClientRect();const h=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return !!h&&(h===e||e.contains(h))};
      return {bar:rect(el('admin-demo-bar')),preview:rect(el('impersonation-banner')),nav:rect(nav),main:rect(main),hero:el('hero-carousel')&&rect(el('hero-carousel')),
        position:getComputedStyle(nav).position,background:getComputedStyle(nav).backgroundColor,
        opacity:getComputedStyle(nav).opacity,alpha:ctx.getImageData(0,0,1,1).data[3],padding:parseFloat(getComputedStyle(main).paddingTop),
        controls:['admin-demo-reset','admin-demo-exit','stop-impersonation-btn','search-icon'].map(hit)};
      """,
      fn geometry ->
        assert geometry["bar"]["height"] > 0
        assert geometry["preview"]["height"] > 0
        assert geometry["nav"]["height"] > 0
        assert geometry["bar"]["bottom"] <= geometry["preview"]["top"] + 1
        assert geometry["preview"]["bottom"] <= geometry["nav"]["top"] + 1
        assert geometry["position"] == "sticky"
        refute geometry["background"] in ["transparent", "rgba(0, 0, 0, 0)"]
        assert geometry["opacity"] == "1"
        assert geometry["alpha"] == 255
        assert geometry["padding"] == 0
        assert geometry["main"]["top"] >= geometry["nav"]["bottom"] - 1
        if geometry["hero"], do: assert(geometry["hero"]["top"] >= geometry["nav"]["bottom"] - 1)
        assert Enum.all?(geometry["controls"])
      end
    )
  end
end
