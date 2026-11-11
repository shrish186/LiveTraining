import sys, numpy as np, matplotlib, importlib.util
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
import cadquery as cq
spec=importlib.util.spec_from_file_location("sc",sys.argv[1]); sc=importlib.util.module_from_spec(spec); spec.loader.exec_module(sc)
body, lid = sc.body(), sc.lid()
fig=plt.figure(figsize=(15,5.2))
ax=fig.add_subplot(1,3,1,projection="3d")
for wp,dz,c in ((body,0,"#4cc9f0"),(lid,sc.OUT_H+8,"#9b87f5")):
    v,t=wp.val().tessellate(0.1); v=np.array([(p.x,p.y,p.z+dz) for p in v])
    ax.add_collection3d(Poly3DCollection(v[np.array(t)],facecolors=c,edgecolors="#00000022",linewidths=0.1))
ax.set_xlim(-24,24);ax.set_ylim(-24,24);ax.set_zlim(-10,38);ax.view_init(28,-60);ax.set_box_aspect((1,1,1));ax.set_axis_off();ax.set_title("body + lid (exploded)")
def section(ax, across, title):
    cutter=(cq.Workplane("YZ") if across else cq.Workplane("XZ")).rect(300,300).extrude(0.01)
    get=(lambda p:(p.y,p.z)) if across else (lambda p:(p.x,p.z))
    for wp,c,lab in ((body,"#4cc9f0","case"),(lid.translate((0,0,sc.OUT_H)),"#9b87f5","lid")):
        first=True
        for f in wp.intersect(cutter).faces().vals():
            v,t=f.tessellate(0.05)
            for tri in t:
                ax.fill(*zip(*[get(v[i]) for i in tri]),color=c,lw=0,label=lab if first else None); first=False
    z0=sc.FLOOR
    if across:
        ax.add_patch(plt.Rectangle((-sc.BATT_W/2,z0),sc.BATT_W,sc.BATT_H,color="#f5c542",label="battery"))
        ax.add_patch(plt.Rectangle((-sc.XIAO_W/2,z0+sc.BATT_H+sc.STACK_GAP),sc.XIAO_W,sc.XIAO_H,color="#3ddc84",label="XIAO"))
        th=np.linspace(-0.6,0.6,100); ax.plot(sc.LEG_RADIUS*np.sin(th), -sc.LEG_RADIUS+sc.LEG_RADIUS*np.cos(th)-0.3,"k--",lw=0.8,label="leg surface")
    else:
        ax.add_patch(plt.Rectangle((-sc.BATT_L/2,z0),sc.BATT_L,sc.BATT_H,color="#f5c542",label="battery"))
        ax.add_patch(plt.Rectangle((sc.IN_L/2-sc.XIAO_L,z0+sc.BATT_H+sc.STACK_GAP),sc.XIAO_L,sc.XIAO_H,color="#3ddc84",label="XIAO (USB-C →)"))
    ax.set_aspect("equal");ax.set_title(title,fontsize=10);ax.legend(loc="upper left",fontsize=7,ncol=2);ax.grid(alpha=.2);ax.set_ylim(-12,26)
section(fig.add_subplot(1,3,2),True,"across the leg: strap loops + curved base (mm)")
section(fig.add_subplot(1,3,3),False,"along the shin: USB-C end at right (mm)")
plt.tight_layout();plt.savefig(sys.argv[2],dpi=110)
