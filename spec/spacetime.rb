require "spec_helper"

describe CFTools::SpaceTime do
  it "spaces the lines out based on the time between them" do
    cf %W[spacetime #{fixture("spacetime/1")} ^\\[([^\\\]]+)\\]]
    expect(output).to say <<EOF
[2013-07-04 16:15:12 -0700] line one
[2013-07-04 16:15:12 -0700] line two

[2013-07-04 16:15:13 -0700] line three
[2013-07-04 16:15:13 -0700] line four










[2013-07-04 16:15:23 -0700] line five
EOF
  end

  context "when the regex fails" do
    it "prints the lines anyway" do
      cf %W[spacetime #{fixture("spacetime/1")} LOL --scale 0.5]
      expect(output).to say <<EOF
[2013-07-04 16:15:12 -0700] line one
[2013-07-04 16:15:12 -0700] line two
[2013-07-04 16:15:13 -0700] line three
[2013-07-04 16:15:13 -0700] line four
[2013-07-04 16:15:23 -0700] line five
EOF
    end
  end

  context "when the regex matches something that ain't no time" do
    it "prints the lines anyway" do
      cf %W[spacetime #{fixture("spacetime/1")} line --scale 0.5]
      expect(output).to say <<EOF
[2013-07-04 16:15:12 -0700] line one
[2013-07-04 16:15:12 -0700] line two
[2013-07-04 16:15:13 -0700] line three
[2013-07-04 16:15:13 -0700] line four
[2013-07-04 16:15:23 -0700] line five
EOF
    end
  end

  context "when a scaling factor is given" do
    it "divides the spacing by the scaling factor" do
      cf %W[spacetime #{fixture("spacetime/1")} ^\\[([^\\\]]+)\\] --scale 0.5]
      expect(output).to say <<EOF
[2013-07-04 16:15:12 -0700] line one
[2013-07-04 16:15:12 -0700] line two

[2013-07-04 16:15:13 -0700] line three
[2013-07-04 16:15:13 -0700] line four





[2013-07-04 16:15:23 -0700] line five
EOF
    end
  end
end
