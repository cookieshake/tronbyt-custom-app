load("render.star", "render")

# buildifier: disable=unused-variable
def main(config):
    return render.Root(
        child = render.Text("NULL"),
    )
